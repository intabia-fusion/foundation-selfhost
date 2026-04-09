#!/usr/bin/env bash

# Script to update Platform Platform version
# Usage: ./set-version.sh <version>
# Example: ./set-version.sh v0.7.400

set -e

CONFIG_DIR="config"
CONFIG_FILE="$CONFIG_DIR/platform.conf"
VERSION_FILE="$CONFIG_DIR/version.txt"
TEMPLATE_VERSION_FILE="templates/version.txt"

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
if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.7.400"
    echo ""
    echo "Current version: $(get_current_version)"
    exit 1
fi

NEW_VERSION="$1"
CURRENT_VERSION=$(get_current_version)

# Validate version format (should start with v and contain numbers)
if [[ ! "$NEW_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "Warning: Version '$NEW_VERSION' doesn't match expected format vX.Y.Z"
    read -p "Continue anyway? (y/N): " confirm
    case "$confirm" in
        [Yy]* ) ;;
        * ) exit 1;;
    esac
fi

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
fi

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
