#!/usr/bin/env bash

# Script to stop Platform services
# Usage: ./down.sh [options]
# Options:
#   --help       Show this help message

CONFIG_FILE="config/platform.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

DC="docker compose --env-file config/platform.conf"
if [ "$DEV_MODE" == "true" ] && [ -f "dev/compose.override.yml" ]; then
    DC="docker compose --env-file config/platform.conf -f compose.yml -f dev/compose.override.yml"
fi

echo "Stopping Platform services..."
$DC down
echo -e "\033[1;32mServices stopped.\033[0m"
