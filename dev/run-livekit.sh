#!/bin/bash

# LiveKit development server startup script
# Starts LiveKit with the dev configuration (requires livekit-server installed locally)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/livekit-config.yaml"

echo "[LiveKit] Starting LiveKit server in development mode..."
echo "[LiveKit] Config: $CONFIG_FILE"
echo "[LiveKit] Port: 7880, RTC UDP: 7882, RTC TCP: 7881"
echo "[LiveKit] API keys: devkey, devkey2"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[LiveKit] ERROR: Config not found: $CONFIG_FILE"
    exit 1
fi

if ! command -v livekit-server &> /dev/null; then
    echo "[LiveKit] ERROR: livekit-server not found"
    echo "[LiveKit] Install: https://docs.livekit.io/home/self-hosting/local/"
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "[LiveKit] On macOS: brew install livekit"
    fi
    exit 1
fi

if lsof -Pi :7880 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "[LiveKit] WARNING: Port 7880 already in use"
fi

livekit-server --config "$CONFIG_FILE"
