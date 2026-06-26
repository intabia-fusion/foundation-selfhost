#!/usr/bin/env bash
#
# Run the platform tool against the local installation.
# Connection parameters come from config/platform.conf (setup.sh output).
#
# Usage:
#   ./run-tool.sh                       # interactive bash shell inside the tool
#   ./run-tool.sh <command> [args...]   # run a tool command, e.g.:
#   ./run-tool.sh create-account user@example.com -p pass -f First -l Last
#   ./run-tool.sh generate-token admin my-team --admin

set -euo pipefail

CONFIG_FILE="config/platform.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[1;31mConfig not found: $CONFIG_FILE. Run ./setup.sh first.\033[0m"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${SECRET:?SECRET missing in $CONFIG_FILE}"
: "${CR_DB_URL:?CR_DB_URL missing in $CONFIG_FILE}"
: "${PLATFORM_VERSION:?PLATFORM_VERSION missing in $CONFIG_FILE}"

NETWORK="${DOCKER_NAME}_platform_net"
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo -e "\033[1;31mNetwork $NETWORK not found. Start the platform first: ./up.sh\033[0m"
    exit 1
fi

# No args -> interactive shell. With args -> run as a tool command via bundle.js.
# The tool entrypoint runs `node` on the first arg, so it must be bundle.js.
if [ $# -eq 0 ]; then
    ENTRY=(bash)
    TTY="-ti"
else
    ENTRY=(bundle.js "$@")
    TTY="-t"
fi

# Extra docker args (mounts, env) can be passed via RUN_TOOL_DOCKER_ARGS,
# e.g. RUN_TOOL_DOCKER_ARGS="-v /abs/backup:/backup" ./run-tool.sh backup-restore /backup ws
read -r -a EXTRA_DOCKER_ARGS <<< "${RUN_TOOL_DOCKER_ARGS:-}"

docker run --rm $TTY \
    --network "$NETWORK" \
    -e SERVER_SECRET="$SECRET" \
    -e SECRET="$SECRET" \
    -e DB_URL="$CR_DB_URL" \
    -e ACCOUNT_DB_URL="$CR_DB_URL" \
    -e ACCOUNTS_DB_URL="$CR_DB_URL" \
    -e STORAGE_CONFIG="${STORAGE_CONFIG}" \
    -e ACCOUNTS_URL="http://account:3000" \
    -e QUEUE_CONFIG="redpanda:9092" \
    -e STATS_URL="http://stats:4900" \
    -e REGION_CONFIG=/var/cfg/region-config.yaml \
    -v "$PWD/config/region-config.yaml":/var/cfg/region-config.yaml:ro \
    ${EXTRA_DOCKER_ARGS[@]+"${EXTRA_DOCKER_ARGS[@]}"} \
    "intabiafusion/tool:${PLATFORM_VERSION}" \
    "${ENTRY[@]}"
