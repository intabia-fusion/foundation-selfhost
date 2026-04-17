#!/usr/bin/env bash

# Script to update Platform Platform version
# Usage: ./set-version.sh [--silent] <version>
# Example: ./set-version.sh v0.7.400
#          ./set-version.sh --silent v0.7.400

set -e

CONFIG_DIR="config"
CONFIG_FILE="$CONFIG_DIR/platform.conf"
VERSION_FILE="$CONFIG_DIR/version.txt"
TEMPLATE_VERSION_FILE="templates/version.txt"

# Default values
SILENT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --silent)
            SILENT=true
            shift
            ;;
        *)
            # Assume it's the version argument
            NEW_VERSION="$1"
            shift
            ;;
    esac
done

# Get current version from template or config
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" | tr -d '[:space:]'
    elif [ -f "$TEMPLATE_VERSION_FILE" ]; then
        cat "$TEMPLATE_VERSION_FILE" | tr -d '[:space:]'
    else
        echo ""
    fi
}

# Check if version argument is provided
if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 [--silent] <version>"
    echo "Example: $0 v0.7.400"
    echo "         $0 --silent v0.7.400"
    echo ""
    echo "Current version: $(get_current_version)"
    exit 1
fi

CURRENT_VERSION=$(get_current_version)

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Update version file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Version updated: ${CURRENT_VERSION:-'(none)'} -> $NEW_VERSION"

# Update config file if it exists
if [ -f "$CONFIG_FILE" ]; then
    sed -i.bak "s/^PLATFORM_VERSION=.*/PLATFORM_VERSION=$NEW_VERSION/" "$CONFIG_FILE"
    sed -i.bak "s/^DESKTOP_CHANNEL=.*/DESKTOP_CHANNEL=$NEW_VERSION/" "$CONFIG_FILE"
    rm -f "$CONFIG_FILE.bak"
    echo "Config file updated: $CONFIG_FILE"
fi

# Source config for DEV_MODE
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

DC="docker compose --env-file config/platform.conf"
if [ "$DEV_MODE" == "true" ] && [ -f "dev/compose.override.yml" ]; then
    DC="docker compose --env-file config/platform.conf -f compose.yml -f dev/compose.override.yml"
    if [ "$LIVEKIT_ENABLED" == "true" ]; then
        DC="$DC --profile livekit-dev"
    fi
elif [ "$LIVEKIT_ENABLED" == "true" ]; then
    DC="$DC --profile livekit"
fi

# Handle image pulling and restart based on silent mode
if [ "$SILENT" == true ]; then
    echo "Silent mode enabled. Skipping interactive prompts."
    echo "Pulling Docker images..."
    $DC pull
    echo "Images pulled successfully."
    echo "Restarting services..."
    $DC up -d
    echo "Services restarted."
else
    # Ask if user wants to pull new images
    read -p "Do you want to pull the new Docker images? (y/N): " pull_images
    case "$pull_images" in
        [Yy]* )
            echo "Pulling Docker images..."
            $DC pull
            echo "Images pulled successfully."
            
            read -p "Do you want to restart services with new version? (y/N): " restart
            case "$restart" in
                [Yy]* )
                    echo "Restarting services..."
                    $DC up -d
                    echo "Services restarted."
                    ;;
                * )
                    echo "Services not restarted. Run './up.sh' when ready."
                    ;;
            esac
            ;;
        * )
            echo "Images not pulled. Run '$DC pull' when ready."
            ;;
    esac
fi
