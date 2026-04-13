#!/usr/bin/env bash

# Script to start Platform Platform
# Usage: ./up.sh [options]
# Options:
#   --recreate   Recreate containers (use after config changes)
#   --build      Rebuild images before starting
#   --pull       Pull latest images before starting
#   --wait       Wait for services to be healthy
#   --logs       Show logs after startup
#   --help       Show this help message

BUILD=false
PULL=false
RECREATE=false
WAIT=false
SHOW_LOGS=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --recreate)
            RECREATE=true
            ;;
        --build)
            BUILD=true
            ;;
        --pull)
            PULL=true
            ;;
        --wait)
            WAIT=true
            ;;
        --logs)
            SHOW_LOGS=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --recreate   Recreate containers (use after config changes)"
            echo "  --build      Rebuild images before starting"
            echo "  --pull       Pull latest images before starting"
            echo "  --wait       Wait for services to be healthy"
            echo "  --logs       Show logs after startup"
            echo "  --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    Start all services"
            echo "  $0 --recreate         Recreate and start containers"
            echo "  $0 --pull             Pull latest images and start"
            exit 0
            ;;
    esac
done

CONFIG_DIR="config"
CONFIG_FILE="$CONFIG_DIR/platform.conf"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration not found. Please run ./setup.sh first."
    exit 1
fi

# Source config for DOCKER_NAME and DEV_MODE
source "$CONFIG_FILE"

# Build docker compose command
DC="docker compose --env-file config/platform.conf"
if [ "$DEV_MODE" == "true" ] && [ -f "dev/compose.override.yml" ]; then
    DC="docker compose --env-file config/platform.conf -f compose.yml -f dev/compose.override.yml"
    if [ "$LIVEKIT_ENABLED" == "true" ]; then
        DC="$DC --profile livekit-dev"
    fi
elif [ "$LIVEKIT_ENABLED" == "true" ]; then
    DC="$DC --profile livekit"
fi

# Pull images if requested
if [ "$PULL" == true ]; then
    echo "Pulling latest Docker images..."
    $DC pull
fi

# Build if requested
if [ "$BUILD" == true ]; then
    echo "Building Docker images..."
    $DC build
fi

# Check required config files exist
if [ ! -f "$CONFIG_DIR/region-config.yaml" ]; then
    echo "Error: region-config.yaml not found. Please run ./setup.sh first."
    exit 1
fi

# Check nginx config exists, generate if not
if [ ! -f "$CONFIG_DIR/nginx.conf" ]; then
    echo "Nginx config not found, generating..."
    ./nginx.sh --no-reload 2>/dev/null || echo "Warning: nginx.sh failed"
fi

# Start services
echo "Starting Platform Platform services..."

if [ "$RECREATE" == true ]; then
    echo "Recreating containers..."
    $DC up -d --force-recreate
else
    $DC up -d
fi

echo -e "\033[1;32mServices started!\033[0m"

# Wait for services to be healthy (if requested)
if [ "$WAIT" == true ]; then
    echo ""
    echo "Waiting for services to be healthy..."
    sleep 5
    
    $DC ps --format "table {{.Service}}\t{{.Status}}"
fi

# Show status
echo ""
echo "Service Status:"
$DC ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

# Show access info
echo ""
echo "Access Information:"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    PROTOCOL=$([ -n "$SECURE" ] && echo "https" || echo "http")
    echo "  URL: ${PROTOCOL}://${HOST_ADDRESS}"
    echo "  Mailpit: http://${HOST_ADDRESS}:${MAILPIT_HTTP_PORT:-8025}"
    if [ -n "$LIVEKIT_ENABLED" ] && [ "$LIVEKIT_ENABLED" == "true" ]; then
        echo "  LiveKit: Enabled (${LIVEKIT_HOST})"
    fi
fi

# Show logs if requested
if [ "$SHOW_LOGS" == true ]; then
    echo ""
    echo "Showing logs (Ctrl+C to exit)..."
    $DC logs -f
fi

echo ""
echo -e "\033[1;32mDone!\033[0m"
echo "Useful commands:"
echo "  $DC ps    - Check service status"
echo "  $DC logs  - View service logs"
echo "  ./cleanup.sh          - Stop all services"

if [ "$DEV_MODE" == "true" ]; then
    echo ""
    echo -e "\033[1;33mDev mode: LiveKit runs locally. Start it in a separate terminal:\033[0m"
    echo "  ./dev/run-livekit.sh"
fi
