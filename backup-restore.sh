#!/usr/bin/env bash
#
# Restore a downloaded backup into the local platform.
# All connection parameters are taken from config/platform.conf (setup.sh output).
#
# Usage:
#   ./backup-restore.sh <backup-dir> <workspace> [date] [-- <extra tool args>]
#
# Example:
#   ./import-backup.mjs --url https://host/_backup/api/backup --token <JWT> --out ./backups/myws
#   ./backup-restore.sh ./backups/myws myws

set -euo pipefail

CONFIG_FILE="config/platform.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[1;31mConfig not found: $CONFIG_FILE. Run ./setup.sh first.\033[0m"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Args
BACKUP_DIR="${1:-}"
WORKSPACE="${2:-}"
DATE=""
EXTRA_ARGS=()
# Restore person/socialId accounts from the backup. On by default - needed when
# migrating a workspace so its members/authors are recreated. Disable with --no-accounts.
RESTORE_ACCOUNTS=true
# Upgrade the workspace to the current model version after restore. On by default -
# the backup is usually from an older version. Disable with --no-upgrade.
UPGRADE=true

shift $(( $# >= 2 ? 2 : $# )) || true
# Optional flags, then optional [date], then optional `-- extra args`
while [ $# -gt 0 ] && [ "${1:-}" != "--" ]; do
    case "$1" in
        --accounts)    RESTORE_ACCOUNTS=true;  shift ;;
        --no-accounts) RESTORE_ACCOUNTS=false; shift ;;
        --upgrade)     UPGRADE=true;  shift ;;
        --no-upgrade)  UPGRADE=false; shift ;;
        *) DATE="$1"; shift ;;
    esac
done
if [ "${1:-}" == "--" ]; then
    shift
    EXTRA_ARGS=("$@")
fi

if [ -z "$BACKUP_DIR" ] || [ -z "$WORKSPACE" ]; then
    echo "Usage: $0 <backup-dir> <workspace> [date] [--no-accounts] [-- <extra tool args>]"
    echo ""
    echo "  <backup-dir>   Local directory with downloaded backup files (from import-backup.mjs)"
    echo "  <workspace>    Target workspace id/url to restore into"
    echo "  [date]         Optional snapshot timestamp (ms). Default: latest"
    echo "  --no-accounts  Do not restore person/socialId accounts (default: restore them)"
    echo "  --no-upgrade   Do not upgrade the workspace after restore (default: upgrade)"
    echo "  -- <args>      Extra args passed to 'tool backup-restore' (e.g. --merge)"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "\033[1;31mBackup directory not found: $BACKUP_DIR\033[0m"
    exit 1
fi

# Resolve absolute path for the volume mount
BACKUP_ABS="$(cd "$BACKUP_DIR" && pwd)"
NETWORK="${DOCKER_NAME}_platform_net"

# Required config values
: "${SECRET:?SECRET missing in $CONFIG_FILE}"
: "${CR_DB_URL:?CR_DB_URL missing in $CONFIG_FILE}"
: "${STORAGE_CONFIG:?STORAGE_CONFIG missing in $CONFIG_FILE}"
: "${PLATFORM_VERSION:?PLATFORM_VERSION missing in $CONFIG_FILE}"

echo -e "\033[1;34mRestoring backup:\033[0m"
echo "  Source:    $BACKUP_ABS"
echo "  Workspace: $WORKSPACE"
echo "  Date:      ${DATE:-latest}"
echo "  Accounts:  ${RESTORE_ACCOUNTS}"
echo "  Upgrade:   ${UPGRADE}"
echo "  Network:   $NETWORK"
echo "  Version:   $PLATFORM_VERSION"
echo ""

# Verify the platform network exists (platform must be up)
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo -e "\033[1;31mNetwork $NETWORK not found. Start the platform first: ./up.sh\033[0m"
    exit 1
fi

CMD=(backup-restore /backup "$WORKSPACE")
[ -n "$DATE" ] && CMD+=("$DATE")
[ "$RESTORE_ACCOUNTS" == true ] && CMD+=(--accounts)
[ ${#EXTRA_ARGS[@]} -gt 0 ] && CMD+=("${EXTRA_ARGS[@]}")

RUN_TOOL_DOCKER_ARGS="-v ${BACKUP_ABS}:/backup" ./run-tool.sh "${CMD[@]}"

echo -e "\n\033[1;32mRestore finished.\033[0m"

# Upgrade the workspace to the current model version (backups are usually older).
if [ "$UPGRADE" == true ]; then
    echo -e "\n\033[1;34mUpgrading workspace ${WORKSPACE} to the current version...\033[0m"
    ./run-tool.sh upgrade-workspace "$WORKSPACE"
    echo -e "\033[1;32mUpgrade finished.\033[0m"
fi

# Upload extra blobs (large media not embedded in the backup) into datalake.
BLOB_DIR="$BACKUP_ABS/blobs"
MANIFEST="$BLOB_DIR/blobs.json"
if [ -f "$MANIFEST" ]; then
    echo -e "\n\033[1;34mUploading extra blobs into datalake...\033[0m"

    # Generate an admin token (system account) and extract the resolved
    # workspace uuid from it.
    TOKEN=$(./run-tool.sh generate-token anticrm@hc.engineering "$WORKSPACE" --admin 2>/dev/null \
        | tr -d '\r' | grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.' | tail -1)

    if [ -z "$TOKEN" ]; then
        echo -e "\033[1;31mFailed to generate token; skipping blob upload.\033[0m"
        exit 1
    fi

    # Decode workspace uuid from the JWT payload (no verification needed).
    WS_UUID=$(node -e '
        const t=process.argv[1].split(".")[1];
        const p=JSON.parse(Buffer.from(t.replace(/-/g,"+").replace(/_/g,"/"),"base64").toString());
        process.stdout.write(p.workspace||"");
    ' "$TOKEN")

    if [ -z "$WS_UUID" ]; then
        echo -e "\033[1;31mCould not resolve workspace uuid; skipping blob upload.\033[0m"
        exit 1
    fi

    DATALAKE_URL="http://localhost:4031/upload/form-data/${WS_UUID}"
    echo "  Workspace uuid: $WS_UUID"
    echo "  Datalake:       $DATALAKE_URL"

    TOTAL=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).blobs.length)' "$MANIFEST")
    i=0
    # Stream "name<TAB>contentType" per blob from the manifest, upload each.
    node -e '
        const m=JSON.parse(require("fs").readFileSync(process.argv[1]));
        for (const b of m.blobs) console.log(b.name+"\t"+(b.contentType||"application/octet-stream"));
    ' "$MANIFEST" | while IFS=$'\t' read -r NAME CTYPE; do
        i=$((i+1))
        FILE="$BLOB_DIR/$NAME"
        if [ ! -f "$FILE" ]; then
            echo "  [$i/$TOTAL] MISSING $NAME (skipped)"
            continue
        fi
        CODE=$(curl -s -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer $TOKEN" \
            -F "file=@${FILE};type=${CTYPE};filename=${NAME}" \
            "$DATALAKE_URL")
        if [ "$CODE" = "200" ]; then
            echo "  [$i/$TOTAL] OK   $NAME"
        else
            echo "  [$i/$TOTAL] FAIL $NAME (HTTP $CODE)"
        fi
    done

    echo -e "\033[1;32mBlob upload finished.\033[0m"
fi
