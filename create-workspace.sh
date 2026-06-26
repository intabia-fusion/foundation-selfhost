#!/usr/bin/env bash
#
# Create a local workspace so a downloaded backup can be restored into it.
#
# A workspace record needs an owner account to exist first. By default this
# script creates a technical admin account and uses it as the temporary owner.
# After 'backup-restore.sh ... --accounts' (the default), the real users from
# the backup are recreated and assigned automatically, so you normally don't
# need to create any user yourself.
#
# All connection parameters are taken from config/platform.conf (setup.sh output).
#
# Usage:
#   ./create-workspace.sh <workspace>
#   # use an existing local account as owner instead of the technical admin:
#   ./create-workspace.sh <workspace> --owner-email <email>

set -euo pipefail

WORKSPACE=""
OWNER_EMAIL=""
ADMIN_EMAIL="admin@platform.local"
ADMIN_SECRET_FILE="config/.admin.secret"

while [ $# -gt 0 ]; do
    case "$1" in
        --owner-email)  OWNER_EMAIL="$2"; shift 2 ;;
        --admin-email)  ADMIN_EMAIL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 <workspace> [--owner-email <email>] [--admin-email <e>]"
            exit 0
            ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *)
            if [ -z "$WORKSPACE" ]; then WORKSPACE="$1"; else echo "Unexpected arg: $1"; exit 1; fi
            shift
            ;;
    esac
done

if [ -z "$WORKSPACE" ]; then
    echo "Usage: $0 <workspace> [--owner-email <email>]"
    exit 1
fi

# Owner: an existing account if provided, otherwise a technical admin we create.
if [ -n "$OWNER_EMAIL" ]; then
    OWNER="$OWNER_EMAIL"
else
    OWNER="$ADMIN_EMAIL"
    # Random admin password, generated once and stored in config/.admin.secret.
    if [ ! -f "$ADMIN_SECRET_FILE" ]; then
        openssl rand -hex 24 > "$ADMIN_SECRET_FILE"
        chmod 600 "$ADMIN_SECRET_FILE"
        echo -e "\033[33mGenerated technical admin password -> ${ADMIN_SECRET_FILE}\033[0m"
    fi
    ADMIN_PASS="$(tr -d '[:space:]' < "$ADMIN_SECRET_FILE")"
    echo -e "\033[1;34mEnsuring technical admin account: ${ADMIN_EMAIL}\033[0m"
    ./run-tool.sh create-account "$ADMIN_EMAIL" -p "$ADMIN_PASS" -f Admin -l Platform \
        || echo -e "\033[33m  admin account already exists, continuing\033[0m"
fi

SOCIAL_ID="email:${OWNER}"

echo -e "\033[1;34mCreating workspace: ${WORKSPACE}\033[0m"
./run-tool.sh create-workspace "$WORKSPACE" "$SOCIAL_ID"

echo -e "\033[1;34mAssigning ${OWNER} to ${WORKSPACE}\033[0m"
./run-tool.sh assign-workspace "$OWNER" "$WORKSPACE"

echo -e "\n\033[1;32mWorkspace '${WORKSPACE}' created.\033[0m"
if [ -z "$OWNER_EMAIL" ]; then
    echo -e "  Technical admin: ${ADMIN_EMAIL} / password in ${ADMIN_SECRET_FILE}"
fi
echo "  Restore (recreates the original users):"
echo "  ./backup-restore.sh ./backups/<ws> ${WORKSPACE}"
