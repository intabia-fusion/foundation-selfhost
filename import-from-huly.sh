#!/usr/bin/env bash
#
# Interactive wizard: download a Huly cloud backup and restore it into the
# local self-hosted platform, step by step.
#
# Steps:
#   1. Ask for backup URL + token (with instructions where to get them)
#   2. Download backup files + blobs (import-backup.mjs)
#   3. Create a local workspace and its owner (create-workspace.sh)
#   4. Restore data and upload blobs (backup-restore.sh)

set -uo pipefail

CONFIG_FILE="config/platform.conf"

C_RESET='\033[0m'; C_B='\033[1m'; C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'
C_YEL='\033[1;33m'; C_RED='\033[1;31m'; C_DIM='\033[2m'

hr ()   { echo -e "${C_DIM}--------------------------------------------------------------${C_RESET}"; }
step () { echo -e "\n${C_BLUE}${C_B}==> $1${C_RESET}"; }
info () { echo -e "${C_DIM}$1${C_RESET}"; }
err ()  { echo -e "${C_RED}$1${C_RESET}"; }

# ask <var> <prompt> [default]
ask () {
    local __var="$1" __prompt="$2" __def="${3:-}" __in
    if [ -n "$__def" ]; then
        read -r -p "$(echo -e "${C_B}${__prompt}${C_RESET} [${__def}]: ")" __in
        __in="${__in:-$__def}"
    else
        read -r -p "$(echo -e "${C_B}${__prompt}${C_RESET}: ")" __in
    fi
    printf -v "$__var" '%s' "$__in"
}

# ask_secret <var> <prompt>
ask_secret () {
    local __var="$1" __prompt="$2" __in
    read -r -s -p "$(echo -e "${C_B}${__prompt}${C_RESET}: ")" __in
    echo
    printf -v "$__var" '%s' "$__in"
}

confirm () {
    local __in
    read -r -p "$(echo -e "${C_B}$1${C_RESET} (y/N): ")" __in
    [[ "$__in" =~ ^[Yy] ]]
}

clear 2>/dev/null || true
echo -e "${C_GREEN}${C_B}Huly Backup Restore Wizard${C_RESET}"
hr

# --- Preconditions ---------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    err "Config not found: $CONFIG_FILE"
    err "Run ./setup.sh first, then ./up.sh to start the platform."
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

NETWORK="${DOCKER_NAME}_platform_net"
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    err "Platform network '$NETWORK' not found. Start the platform first: ./up.sh"
    exit 1
fi
if ! command -v node >/dev/null 2>&1; then
    err "node is required (for import-backup.mjs). Install Node.js first."
    exit 1
fi

# --- Step 1: backup URL ----------------------------------------------------
step "Step 1/5 - Backup URL"
cat <<EOF
$(info "Open your workspace in the Huly web app and go to:")
$(info "  https://huly.app/workbench/<workspace>/setting/setting/backup")
$(info "Under 'Backup Files' -> 'The URL of a backup directory ...' click")
$(info "'Copy to clipboard'. It looks like:")
$(info "  https://backup.huly.app/api/backup/<workspace-id>/index.html")
EOF
ask BACKUP_URL "Paste the backup URL"
if [ -z "$BACKUP_URL" ]; then err "Backup URL is required."; exit 1; fi

# --- Step 2: token ---------------------------------------------------------
step "Step 2/5 - Access token"
cat <<EOF
$(info "On the same Backup settings page, next to")
$(info "'A bearer token is required to access the backup' click 'Copy to clipboard'.")
$(info "Paste it below (input hidden).")
EOF
ask_secret BACKUP_TOKEN "Paste the bearer token"
if [ -z "$BACKUP_TOKEN" ]; then err "Token is required."; exit 1; fi

# --- Step 3: target workspace ----------------------------------------------
step "Step 3/4 - Local workspace"
cat <<EOF
$(info "A new local workspace will be created and the backup restored into it.")
$(info "Pick any readable name (not a UUID), e.g. 'my-team' or 'acme'.")
$(info "")
$(info "You do NOT need to create any user: the original users from the backup")
$(info "are recreated automatically. They sign in by email (OTP via Mailpit).")
EOF
ask WS_NAME "Workspace name"
if [ -z "$WS_NAME" ]; then err "Workspace name is required."; exit 1; fi

# Download into a folder keyed by the Huly workspace UUID (from the backup URL),
# NOT by the chosen local name. This way re-running with a different name reuses
# the already-downloaded data and never re-downloads.
HULY_WS=$(printf '%s' "$BACKUP_URL" | sed -E 's#.*/api/backup/([^/]+).*#\1#')
if [ -z "$HULY_WS" ]; then err "Could not parse workspace UUID from backup URL."; exit 1; fi
OUT_DIR="./backups/${HULY_WS}"

# --- Summary ---------------------------------------------------------------
step "Summary"
echo -e "  Backup URL:  ${C_B}${BACKUP_URL}${C_RESET}"
echo -e "  Token:       ${C_B}${BACKUP_TOKEN:0:12}...${C_RESET}"
echo -e "  Workspace:   ${C_B}${WS_NAME}${C_RESET}"
echo -e "  Users:       ${C_B}restored from backup${C_RESET} ${C_DIM}(sign in by email + OTP)${C_RESET}"
echo -e "  Download to: ${C_B}${OUT_DIR}${C_RESET} ${C_DIM}(keyed by Huly UUID, reused on re-run)${C_RESET}"
[ -d "$OUT_DIR" ] && echo -e "  ${C_YEL}Existing download found - only missing files will be fetched.${C_RESET}"
hr
if ! confirm "Proceed?"; then echo "Cancelled."; exit 0; fi

# Token is passed via a temp file to avoid leaking it in the process list.
TOKEN_FILE="$(mktemp)"
trap 'rm -f "$TOKEN_FILE"' EXIT
printf '%s' "$BACKUP_TOKEN" > "$TOKEN_FILE"

# --- Step 4: download ------------------------------------------------------
step "Step 4/4 - Downloading backup"
if ! node import-backup.mjs --url "$BACKUP_URL" --token-file "$TOKEN_FILE" --out "$OUT_DIR"; then
    err "Download failed."
    exit 1
fi

# --- Create workspace ------------------------------------------------------
step "Creating workspace and restoring"
if ! ./create-workspace.sh "$WS_NAME"; then
    err "Workspace creation failed."
    exit 1
fi

# --- Step 5b: restore + blobs ----------------------------------------------
if ! ./backup-restore.sh "$OUT_DIR" "$WS_NAME"; then
    err "Restore failed."
    exit 1
fi

hr
echo -e "${C_GREEN}${C_B}Done!${C_RESET}"
echo -e "Workspace ${C_B}${WS_NAME}${C_RESET} is restored with its original users."
echo -e "Open ${C_B}http${SECURE:+s}://${HOST_ADDRESS}${C_RESET} and sign in with any of those"
echo -e "emails - the login code (OTP) arrives in Mailpit at ${C_B}http://${HOST_ADDRESS%%:*}:${MAILPIT_HTTP_PORT:-8025}${C_RESET}."
