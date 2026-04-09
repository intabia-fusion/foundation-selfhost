#!/usr/bin/env bash

# Script to stop and clean up Platform Platform services
# Usage: ./cleanup.sh [options]
# Options:
#   --volumes    Also remove Docker volumes (WARNING: this will delete all data!)
#   --images     Also remove Docker images
#   --all        Remove volumes, images, and generated configs
#   --help       Show this help message

set -e

REMOVE_VOLUMES=false
REMOVE_IMAGES=false
REMOVE_CONFIGS=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --volumes)
            REMOVE_VOLUMES=true
            ;;
        --images)
            REMOVE_IMAGES=true
            ;;
        --all)
            REMOVE_VOLUMES=true
            REMOVE_IMAGES=true
            REMOVE_CONFIGS=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --volumes    Remove Docker volumes (WARNING: deletes all data!)"
            echo "  --images     Remove Docker images"
            echo "  --all        Remove volumes, images, and generated configs"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    Stop all services (keep data)"
            echo "  $0 --volumes          Stop and remove all data"
            echo "  $0 --all              Complete cleanup (factory reset)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Confirmation for destructive operations
if [ "$REMOVE_VOLUMES" == true ] || [ "$REMOVE_CONFIGS" == true ]; then
    echo -e "\033[1;31mWARNING: This will delete all data!\033[0m"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# Source config for DEV_MODE
CONFIG_FILE="config/platform.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

DC="docker compose --env-file config/platform.conf"
if [ "$DEV_MODE" == "true" ] && [ -f "dev/compose.override.yml" ]; then
    DC="docker compose --env-file config/platform.conf -f compose.yml -f dev/compose.override.yml"
fi

# Build down flags
DOWN_FLAGS=""
if [ "$REMOVE_VOLUMES" == true ]; then
    DOWN_FLAGS="$DOWN_FLAGS -v"
fi
if [ "$REMOVE_IMAGES" == true ]; then
    DOWN_FLAGS="$DOWN_FLAGS --rmi all"
fi

echo "Stopping Platform Platform services..."
$DC down $DOWN_FLAGS

if [ "$REMOVE_VOLUMES" == true ]; then
    echo -e "\033[33mVolumes removed. All data has been deleted.\033[0m"
fi

if [ "$REMOVE_IMAGES" == true ]; then
    echo -e "\033[33mImages removed.\033[0m"
fi

if [ "$REMOVE_CONFIGS" == true ]; then
    echo "Removing generated configuration files, secrets, and data..."
    rm -rf config/
    if [ -d "data" ]; then
        rm -rf data/*
    fi
    echo -e "\033[33mConfiguration, secrets, and data removed.\033[0m"
    echo "To start fresh, run: ./setup.sh"
fi

echo -e "\033[1;32mCleanup complete!\033[0m"

# Show status
echo ""
echo "Docker status:"
docker ps -a --filter "name=platform" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "No platform containers found"
