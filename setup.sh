#!/usr/bin/env bash

# Handle Ctrl+C (SIGINT) and SIGTERM gracefully
trap 'echo -e "\n\033[1;31mSetup interrupted. Exiting...\033[0m"; exit 130' INT TERM

CONFIG_DIR="config"
CONFIG_FILE="$CONFIG_DIR/platform.conf"

# Default values
SILENT=false
RESET_VOLUMES=false
USE_LIVEKIT=""
HOST=""
LIVEKIT_HOST=""
HTTP_PORT=""
SSL=""
VERSION=""
DEV_MODE=false

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup script for Platform.

OPTIONS:
  --silent              Run without interactive prompts (use defaults or provided values)
  --host <address>      Set host address (e.g., localhost or platform.example.com)
  --port <port>         Set HTTP port (default: 80)
  --ssl                 Enable SSL/HTTPS
  --use-livekit         Enable LiveKit for audio/video calls
  --livekit-host <url>  Set LiveKit server URL (default: ws://<host>/livekit)
  --dev                 Development mode (localhost, LiveKit with devkey, no SSL)
  --version <ver>       Set platform version (e.g., v0.7.357). Fetches latest from GitHub if not set.
  --reset-volumes       Reset volume paths to empty (use Docker named volumes)
  --help                Show this help message

EXAMPLES:
  $0                           Interactive setup
  $0 --silent                  Non-interactive setup with defaults
  $0 --silent --host myhost    Setup with specific host
  $0 --silent --use-livekit    Enable LiveKit in silent mode
  $0 --host localhost --port 8080 --use-livekit
  $0 --silent --version v0.7.357   Setup with specific version
  $0 --dev                         Dev mode with local LiveKit

DEFAULT VALUES (in silent mode):
  Host:         localhost
  Port:         80
  SSL:          disabled
  LiveKit:      disabled
  Data paths:   ./data/<service>
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --silent)
            SILENT=true
            shift
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --ssl)
            SSL="true"
            shift
            ;;
        --use-livekit)
            USE_LIVEKIT="true"
            shift
            ;;
        --livekit-host)
            LIVEKIT_HOST="$2"
            shift 2
            ;;
        --dev)
            DEV_MODE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --reset-volumes)
            RESET_VOLUMES=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Handle --reset-volumes
if [ "$RESET_VOLUMES" == true ]; then
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "\033[33mResetting all volume paths to default Docker named volumes.\033[0m"
        sed -i \
            -e '/^VOLUME_ELASTIC_PATH=/s|=.*|=|' \
            -e '/^VOLUME_FILES_PATH=/s|=.*|=|' \
            -e '/^VOLUME_POSTGRES_DATA_PATH=/s|=.*|=|' \
            -e '/^VOLUME_REDPANDA_PATH=/s|=.*|=|' \
            -e '/^VOLUME_MAILPIT_PATH=/s|=.*|=|' \
            "$CONFIG_FILE"
        echo "Volume paths reset. Run ./up.sh to apply changes."
    else
        echo "Config file not found. Nothing to reset."
    fi
    exit 0
fi

# Source existing config if available
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

# Dev mode: set defaults for local development
if [ "$DEV_MODE" == true ]; then
    echo -e "\033[1;33mDev mode enabled.\033[0m"
    HOST="${HOST:-localhost}"
    HTTP_PORT="${HTTP_PORT:-8083}"
    SSL=""
    USE_LIVEKIT="true"
    SILENT=true

    # Dev LiveKit: local server with static credentials (devkey/secret)
    _LIVEKIT_API_KEY="devkey"
    _LIVEKIT_API_SECRET="secret"
    LIVEKIT_HOST="${LIVEKIT_HOST:-ws://localhost:7880}"

    # Copy dev livekit configs to config/
    if [ -f "dev/livekit-config.yaml" ]; then
        cp dev/livekit-config.yaml "$CONFIG_DIR/livekit.yaml"
        echo "Dev LiveKit config copied."
    fi
    if [ -f "dev/livekit-egress-config.yaml" ]; then
        cp dev/livekit-egress-config.yaml "$CONFIG_DIR/livekit-egress-config.yaml"
        echo "Dev LiveKit Egress config copied."
    fi
fi

# Fetch latest version from GitHub
GITHUB_TAGS_URL="https://api.github.com/repos/intabia-fusion/foundation/tags?per_page=1"
LATEST_VERSION=""
if command -v curl &>/dev/null; then
    LATEST_VERSION=$(curl -sf "$GITHUB_TAGS_URL" | grep -m1 '"name"' | sed 's/.*"name": *"\([^"]*\)".*/\1/')
fi

# Determine current version from config or fallback
if [ -f "$CONFIG_DIR/version.txt" ]; then
    CURRENT_VERSION=$(cat "$CONFIG_DIR/version.txt" | tr -d '[:space:]')
elif [ -f "templates/version.txt" ]; then
    CURRENT_VERSION=$(cat "templates/version.txt" | tr -d '[:space:]')
else
    CURRENT_VERSION=""
fi

# Resolve platform version
if [ -n "$VERSION" ]; then
    # Explicit --version flag
    PLATFORM_VERSION="$VERSION"
elif [ "$SILENT" == true ]; then
    # Silent mode: use latest from GitHub, fall back to current/template
    PLATFORM_VERSION="${LATEST_VERSION:-$CURRENT_VERSION}"
else
    # Interactive mode: prompt user
    if [ -n "$LATEST_VERSION" ]; then
        VERSION_DEFAULT="$LATEST_VERSION"
        VERSION_HINT="latest: $LATEST_VERSION"
    elif [ -n "$CURRENT_VERSION" ]; then
        VERSION_DEFAULT="$CURRENT_VERSION"
        VERSION_HINT="current: $CURRENT_VERSION"
    else
        VERSION_DEFAULT=""
        VERSION_HINT="no version found"
    fi

    if [ -n "$CURRENT_VERSION" ] && [ -n "$LATEST_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        VERSION_HINT="current: $CURRENT_VERSION, latest: $LATEST_VERSION"
    fi

    read -p "Enter platform version [$VERSION_HINT]: " input
    PLATFORM_VERSION="${input:-$VERSION_DEFAULT}"
fi

if [ -z "$PLATFORM_VERSION" ]; then
    echo -e "\033[1;31mError: Could not determine platform version. Use --version flag or check internet connection.\033[0m"
    exit 1
fi

# Save version
echo "$PLATFORM_VERSION" > "$CONFIG_DIR/version.txt"
export PLATFORM_VERSION
export DESKTOP_CHANNEL=$PLATFORM_VERSION
PREV_LIVEKIT_TURN_DOMAIN="${LIVEKIT_TURN_DOMAIN}"

# Set values from arguments or prompt
if [ "$SILENT" == true ]; then
    # Silent mode - use defaults or provided values
    _HOST_ADDRESS="${HOST:-${HOST_ADDRESS:-localhost}}"
    _HTTP_PORT="${HTTP_PORT:-${HTTP_PORT:-80}}"
    _SECURE="${SSL:-${SECURE:-}}"
    _LIVEKIT_ENABLED="${USE_LIVEKIT:-false}"

    # Default volume paths
    _VOLUME_ELASTIC_PATH="./data/elastic"
    _VOLUME_FILES_PATH="./data/minio"
    _VOLUME_POSTGRES_DATA_PATH="./data/postgres"
    _VOLUME_REDPANDA_PATH="./data/redpanda"
    _VOLUME_MAILPIT_PATH="./data/mailpit"

    echo "Silent mode enabled. Using defaults:"
    echo "  Host: $_HOST_ADDRESS"
    echo "  Port: $_HTTP_PORT"
    echo "  SSL: ${_SECURE:+enabled}${_SECURE:-disabled}"
    echo "  LiveKit: $_LIVEKIT_ENABLED"
else
    # Interactive mode - prompt for values

    # Host address
    RAW_HOST_INPUT=""
    while true; do
        if [[ -n "$HOST" ]]; then
            _HOST_ADDRESS="$HOST"
            break
        elif [[ -n "$HOST_ADDRESS" ]]; then
            prompt_type="current"
            prompt_value="${HOST_ADDRESS}"
        else
            prompt_type="default"
            prompt_value="localhost"
        fi
        read -p "Enter the host address [${prompt_type}: ${prompt_value}]: " input
        RAW_HOST_INPUT="${input:-${HOST_ADDRESS:-localhost}}"
        _HOST_ADDRESS="$RAW_HOST_INPUT"
        break
    done

    HOST_ONLY="${_HOST_ADDRESS%%:*}"

    # HTTP Port
    while true; do
        if [[ -n "$HTTP_PORT" ]]; then
            _HTTP_PORT="$HTTP_PORT"
            break
        elif [[ -n "$HTTP_PORT" ]]; then
            prompt_type="current"
            prompt_value="${HTTP_PORT}"
        else
            prompt_type="default"
            prompt_value="80"
        fi
        read -p "Enter the port for HTTP [${prompt_type}: ${prompt_value}]: " input
        _HTTP_PORT="${input:-${HTTP_PORT:-80}}"
        if [[ "$_HTTP_PORT" =~ ^[0-9]+$ && "$_HTTP_PORT" -ge 1 && "$_HTTP_PORT" -le 65535 ]]; then
            break
        else
            echo "Invalid port. Please enter a number between 1 and 65535."
        fi
    done

    # SSL
    if [[ -n "$SSL" ]]; then
        _SECURE="$SSL"
    elif [[ "$HOST_ONLY" != "localhost" && "$HOST_ONLY" != "127.0.0.1" && ! "$HOST_ONLY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        while true; do
            if [[ -n "$SECURE" ]]; then
                prompt_type="current"
                prompt_value="Yes"
            else
                prompt_type="default"
                prompt_value="No"
            fi
            read -p "Will you serve Platform over SSL? (y/n) [${prompt_type}: ${prompt_value}]: " input
            case "${input}" in
                [Yy]* ) _SECURE="true"; break;;
                [Nn]* ) _SECURE=""; break;;
                "" ) _SECURE="${SECURE:+true}"; break;;
                * ) echo "Invalid input. Please enter Y or N.";;
            esac
        done
    else
        _SECURE=""
    fi

    # Volume configuration
    echo -e "\n\033[1;34mDocker Volume Configuration:\033[0m"
    echo "Data will be stored in ./data/ subdirectories by default."
    echo "Enter a custom path, or press Enter to use the default, or type 'none' for Docker named volumes."

    DEFAULT_ELASTIC_PATH="./data/elastic"
    DEFAULT_FILES_PATH="./data/minio"
    DEFAULT_POSTGRES_PATH="./data/postgres"
    DEFAULT_REDPANDA_PATH="./data/redpanda"
    DEFAULT_MAILPIT_PATH="./data/mailpit"

    # Elasticsearch
    if [[ -n "$VOLUME_ELASTIC_PATH" ]]; then current="$VOLUME_ELASTIC_PATH"; else current="$DEFAULT_ELASTIC_PATH"; fi
    read -p "Enter path for Elasticsearch data [$current]: " input
    if [[ "$input" == "none" ]]; then _VOLUME_ELASTIC_PATH=""; else _VOLUME_ELASTIC_PATH="${input:-$current}"; fi

    # Files
    if [[ -n "$VOLUME_FILES_PATH" ]]; then current="$VOLUME_FILES_PATH"; else current="$DEFAULT_FILES_PATH"; fi
    read -p "Enter path for Files/Minio data [$current]: " input
    if [[ "$input" == "none" ]]; then _VOLUME_FILES_PATH=""; else _VOLUME_FILES_PATH="${input:-$current}"; fi

    # PostgreSQL
    if [[ -n "$VOLUME_POSTGRES_DATA_PATH" ]]; then current="$VOLUME_POSTGRES_DATA_PATH"; else current="$DEFAULT_POSTGRES_PATH"; fi
    read -p "Enter path for PostgreSQL data [$current]: " input
    if [[ "$input" == "none" ]]; then _VOLUME_POSTGRES_DATA_PATH=""; else _VOLUME_POSTGRES_DATA_PATH="${input:-$current}"; fi

    # Redpanda
    if [[ -n "$VOLUME_REDPANDA_PATH" ]]; then current="$VOLUME_REDPANDA_PATH"; else current="$DEFAULT_REDPANDA_PATH"; fi
    read -p "Enter path for Redpanda data [$current]: " input
    if [[ "$input" == "none" ]]; then _VOLUME_REDPANDA_PATH=""; else _VOLUME_REDPANDA_PATH="${input:-$current}"; fi

    # Mailpit
    if [[ -n "$VOLUME_MAILPIT_PATH" ]]; then current="$VOLUME_MAILPIT_PATH"; else current="$DEFAULT_MAILPIT_PATH"; fi
    read -p "Enter path for Mailpit data [$current]: " input
    if [[ "$input" == "none" ]]; then _VOLUME_MAILPIT_PATH=""; else _VOLUME_MAILPIT_PATH="${input:-$current}"; fi
fi

# Generate secrets (only if not already present — never overwrite existing secrets)
# If data directories exist but secrets are missing, warn about potential mismatch
SECRETS_GENERATED=false

if [ ! -f "$CONFIG_DIR/.platform.secret" ]; then
    openssl rand -hex 32 > "$CONFIG_DIR/.platform.secret"
    echo "Platform secret generated."
    SECRETS_GENERATED=true
fi

if [ ! -f "$CONFIG_DIR/.postgres.secret" ]; then
    if [ -d "data/postgres" ] && [ "$(ls -A data/postgres 2>/dev/null)" ]; then
        echo -e "\033[1;31mWARNING: Postgres data exists but secret is missing.\033[0m"
        echo -e "\033[1;31mNew secret won't match the existing database. Remove data/postgres/ or restore the old secret.\033[0m"
    fi
    openssl rand -hex 32 > "$CONFIG_DIR/.postgres.secret"
    echo "Postgres secret generated."
    SECRETS_GENERATED=true
fi

if [ ! -f "$CONFIG_DIR/.rp.secret" ]; then
    if [ -d "data/redpanda" ] && [ "$(ls -A data/redpanda 2>/dev/null)" ]; then
        echo -e "\033[1;31mWARNING: Redpanda data exists but secret is missing.\033[0m"
        echo -e "\033[1;31mNew secret won't match the existing cluster. Remove data/redpanda/ or restore the old secret.\033[0m"
    fi
    openssl rand -hex 32 > "$CONFIG_DIR/.rp.secret"
    echo "Redpanda secret generated."
    SECRETS_GENERATED=true
fi

if [ "$SECRETS_GENERATED" == true ] && ([ -d "data/postgres" ] && [ "$(ls -A data/postgres 2>/dev/null)" ] || [ -d "data/redpanda" ] && [ "$(ls -A data/redpanda 2>/dev/null)" ]); then
    echo -e "\033[1;33mExisting data detected with new secrets. Consider running './cleanup.sh --all' for a clean start.\033[0m"
fi

# LiveKit configuration
if [ "$SILENT" == true ]; then
    if [ "$USE_LIVEKIT" == "true" ]; then
        _LIVEKIT_ENABLED=true
        # Generate credentials if not provided
        if [[ -z "$_LIVEKIT_API_KEY" || -z "$_LIVEKIT_API_SECRET" ]]; then
            echo "Generating LiveKit credentials..."
            rm -f livekit.yaml 2>/dev/null
            if docker run --rm -v "$PWD":/output -w /output livekit/generate --local 2>/dev/null; then
                if [[ -f "livekit.yaml" ]]; then
                    LIVEKIT_KEYS_LINE=$(awk '/^keys:/ {getline; gsub(/^[[:space:]]+/, "", $0); print $0; exit}' livekit.yaml)
                    if [[ -n "$LIVEKIT_KEYS_LINE" ]]; then
                        _LIVEKIT_API_KEY=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f1 | tr -d '[:space:]')
                        _LIVEKIT_API_SECRET=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
                        echo "Credentials: $_LIVEKIT_API_KEY"
                    fi
                    rm -f livekit.yaml
                fi
            fi
        fi
    fi
else
    # Interactive LiveKit setup
    LIVEKIT_DEFAULT_CHOICE="${USE_LIVEKIT:-${LIVEKIT_API_KEY:+Y}}"
    _LIVEKIT_ENABLED=false
    _LIVEKIT_API_KEY="${LIVEKIT_API_KEY:-}"
    _LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:-}"

    read -p "Enable LiveKit (audio & video calls)? (y/N) [default: ${LIVEKIT_DEFAULT_CHOICE:-N}]: " input
    case "$input" in
        [Yy]*) _LIVEKIT_ENABLED=true ;;
        "") [[ "$LIVEKIT_DEFAULT_CHOICE" == "Y" ]] && _LIVEKIT_ENABLED=true ;;
    esac

    if [[ "$_LIVEKIT_ENABLED" == true ]]; then
        # Generate or reuse credentials
        if [[ -z "$_LIVEKIT_API_KEY" || -z "$_LIVEKIT_API_SECRET" ]]; then
            echo "Generating LiveKit credentials..."
            rm -f livekit.yaml 2>/dev/null
            if docker run --rm -v "$PWD":/output -w /output livekit/generate --local 2>/dev/null; then
                if [[ -f "livekit.yaml" ]]; then
                    LIVEKIT_KEYS_LINE=$(awk '/^keys:/ {getline; gsub(/^[[:space:]]+/, "", $0); print $0; exit}' livekit.yaml)
                    if [[ -n "$LIVEKIT_KEYS_LINE" ]]; then
                        _LIVEKIT_API_KEY=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f1 | tr -d '[:space:]')
                        _LIVEKIT_API_SECRET=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
                        echo "Generated: $_LIVEKIT_API_KEY"
                    fi
                    rm -f livekit.yaml
                fi
            fi
        fi

        # Prompt if still missing
        if [[ -z "$_LIVEKIT_API_KEY" ]]; then
            echo "LiveKit credentials not found."
            while [[ -z "$_LIVEKIT_API_KEY" ]]; do
                read -p "Enter LiveKit API Key: " _LIVEKIT_API_KEY
            done
            while [[ -z "$_LIVEKIT_API_SECRET" ]]; do
                read -s -p "Enter LiveKit API Secret: " secret_input
                echo
                [[ -n "$secret_input" ]] && _LIVEKIT_API_SECRET="$secret_input"
            done
        fi
    fi
fi

# Calculate derived values
HOST_ONLY="${_HOST_ADDRESS%%:*}"
if [[ -n "$_SECURE" ]]; then
    LIVEKIT_EXTERNAL_PORT="${_HTTP_PORT:-443}"
    [[ "$LIVEKIT_EXTERNAL_PORT" == "443" ]] && LIVEKIT_EXTERNAL_PORT=""
    LIVEKIT_SCHEME="wss"
else
    LIVEKIT_EXTERNAL_PORT="${_HTTP_PORT:-80}"
    [[ "$LIVEKIT_EXTERNAL_PORT" == "80" ]] && LIVEKIT_EXTERNAL_PORT=""
    LIVEKIT_SCHEME="ws"
fi

if [[ "$_LIVEKIT_ENABLED" == true ]]; then
    if [[ -n "$LIVEKIT_HOST" ]]; then
        _LIVEKIT_HOST="$LIVEKIT_HOST"
    else
        LIVEKIT_BASE_HOST="$HOST_ONLY"
        [[ -n "$LIVEKIT_EXTERNAL_PORT" ]] && LIVEKIT_BASE_HOST="${LIVEKIT_BASE_HOST}:${LIVEKIT_EXTERNAL_PORT}"
        _LIVEKIT_HOST="${LIVEKIT_SCHEME}://${LIVEKIT_BASE_HOST}/livekit"
    fi
    LIVEKIT_TURN_DOMAIN="${HOST_ONLY}"
else
    _LIVEKIT_HOST=""
    _LIVEKIT_API_KEY=""
    _LIVEKIT_API_SECRET=""
    LIVEKIT_TURN_DOMAIN=""
fi

# Ensure volume paths have ./ prefix
[[ -n "$_VOLUME_ELASTIC_PATH" && ! "$_VOLUME_ELASTIC_PATH" =~ ^(/|\./) ]] && export VOLUME_ELASTIC_PATH="./$_VOLUME_ELASTIC_PATH" || export VOLUME_ELASTIC_PATH=$_VOLUME_ELASTIC_PATH
[[ -n "$_VOLUME_FILES_PATH" && ! "$_VOLUME_FILES_PATH" =~ ^(/|\./) ]] && export VOLUME_FILES_PATH="./$_VOLUME_FILES_PATH" || export VOLUME_FILES_PATH=$_VOLUME_FILES_PATH
[[ -n "$_VOLUME_POSTGRES_DATA_PATH" && ! "$_VOLUME_POSTGRES_DATA_PATH" =~ ^(/|\./) ]] && export VOLUME_POSTGRES_DATA_PATH="./$_VOLUME_POSTGRES_DATA_PATH" || export VOLUME_POSTGRES_DATA_PATH=$_VOLUME_POSTGRES_DATA_PATH
[[ -n "$_VOLUME_REDPANDA_PATH" && ! "$_VOLUME_REDPANDA_PATH" =~ ^(/|\./) ]] && export VOLUME_REDPANDA_PATH="./$_VOLUME_REDPANDA_PATH" || export VOLUME_REDPANDA_PATH=$_VOLUME_REDPANDA_PATH
[[ -n "$_VOLUME_MAILPIT_PATH" && ! "$_VOLUME_MAILPIT_PATH" =~ ^(/|\./) ]] && export VOLUME_MAILPIT_PATH="./$_VOLUME_MAILPIT_PATH" || export VOLUME_MAILPIT_PATH=$_VOLUME_MAILPIT_PATH

# Export variables
export PLATFORM_SECRET=$(cat "$CONFIG_DIR/.platform.secret")
export POSTGRES_SECRET=$(cat "$CONFIG_DIR/.postgres.secret")
export REDPANDA_SECRET=$(cat "$CONFIG_DIR/.rp.secret")
export HOST_ADDRESS=$_HOST_ADDRESS
export SECURE=$_SECURE
export HTTP_PORT=$_HTTP_PORT
export HTTP_BIND=$HTTP_BIND
export TITLE=${TITLE:-Platform}
export DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-ru}
export LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
export POSTGRES_DB=${POSTGRES_DB:-platform}
export POSTGRES_USER=${POSTGRES_USER:-platform}
export REDPANDA_ADMIN_USER=${REDPANDA_ADMIN_USER:-superadmin}
export DOCKER_NAME=${DOCKER_NAME:-platform}
export DEV_MODE=$DEV_MODE
export SECRET=$PLATFORM_SECRET
export STORAGE_CONFIG=${STORAGE_CONFIG:-datalake|http://datalake:4031}
export LIVEKIT_HOST=${_LIVEKIT_HOST}
export LIVEKIT_API_KEY=${_LIVEKIT_API_KEY}
export LIVEKIT_API_SECRET=${_LIVEKIT_API_SECRET}
export LIVEKIT_ENABLED=${_LIVEKIT_ENABLED}
export LIVEKIT_TURN_DOMAIN=${LIVEKIT_TURN_DOMAIN}
export STT_PROVIDER=${STT_PROVIDER:-openai}
export STT_URL=${STT_URL:-http://oaitt:9007}
export STT_API_KEY=${STT_API_KEY:-key}
export STT_MODEL=${STT_MODEL}
export OPENAI_API_KEY=${OPENAI_API_KEY:-token}
export OPENAI_BASE_URL=${OPENAI_BASE_URL:-http://localhost:1234/v1/}
export OPENAI_SUMMARY_MODEL=${OPENAI_SUMMARY_MODEL:-openai/gpt-oss-20b}
export OPENAI_TRANSLATE_MODEL=${OPENAI_TRANSLATE_MODEL:-openai/gpt-oss-20b}

# Generate platform.conf
envsubst < templates/platform.conf.template > "$CONFIG_FILE"
source "$CONFIG_FILE"
export CR_DB_URL=$CR_DB_URL

# Summary
echo -e "\n\033[1;34mConfiguration Summary:\033[0m"
[[ "$DEV_MODE" == true ]] && echo -e "Mode: \033[1;33mDevelopment\033[0m"
echo -e "Version: \033[1;32m$PLATFORM_VERSION\033[0m"
echo -e "Host Address: \033[1;32m$_HOST_ADDRESS\033[0m"
echo -e "HTTP Port: \033[1;32m$_HTTP_PORT\033[0m"
[[ -n "$SECURE" ]] && echo -e "SSL: \033[1;32mYes\033[0m" || echo -e "SSL: \033[1;31mNo\033[0m"
echo -e "Volumes: elastic=${_VOLUME_ELASTIC_PATH:-Docker}, files=${_VOLUME_FILES_PATH:-Docker}, postgres=${_VOLUME_POSTGRES_DATA_PATH:-Docker}, redpanda=${_VOLUME_REDPANDA_PATH:-Docker}, mailpit=${_VOLUME_MAILPIT_PATH:-Docker}"
[[ "$_LIVEKIT_ENABLED" == true ]] && echo -e "LiveKit: \033[1;32mEnabled\033[0m ($_LIVEKIT_HOST)" || echo -e "LiveKit: \033[1;31mDisabled\033[0m"
echo -e "Mailpit UI: \033[1;32mhttp://${_HOST_ADDRESS}:${MAILPIT_HTTP_PORT:-8025}\033[0m"

# Create data directories
mkdir -p data/postgres data/minio data/elastic data/redpanda data/mailpit
mkdir -p data/print data/analytics data/export data/time-machine data/livekit-egress
mkdir -p data/link-preview data/activity data/notification

# Generate configs from templates
if [[ -f templates/branding.json.template ]]; then
    envsubst < templates/branding.json.template > "$CONFIG_DIR/branding.json"
    echo "Branding configuration updated."
fi

if [[ -f templates/region-config.yaml.template ]]; then
    envsubst < templates/region-config.yaml.template > "$CONFIG_DIR/region-config.yaml"
    echo "Region configuration updated."
fi

if [[ "$_LIVEKIT_ENABLED" == true && "$DEV_MODE" != true ]]; then
    if [[ -f templates/livekit-egress-config.yaml.template ]]; then
        envsubst < templates/livekit-egress-config.yaml.template > "$CONFIG_DIR/livekit-egress-config.yaml"
        echo "LiveKit Egress configuration updated."
    fi
    if [[ -f templates/livekit.yaml.template ]]; then
        envsubst < templates/livekit.yaml.template > "$CONFIG_DIR/livekit.yaml"
        echo "LiveKit configuration updated."
    fi
fi

# Remove legacy .env symlink if it exists
if [ -L ".env" ]; then
    rm -f .env
    echo "Removed legacy .env symlink (config is now read directly from $CONFIG_FILE)."
fi

# Run nginx.sh
echo -e "\033[1;32mSetup complete! Generating nginx.conf...\033[0m"
./nginx.sh

# Ask to start services (unless in silent mode)
if [ "$SILENT" == false ]; then
    read -p "Do you want to start services now? (Y/n): " RUN_DOCKER
    case "${RUN_DOCKER:-Y}" in
        [Yy]* )
            echo -e "\033[1;32mStarting services...\033[0m"
            ./up.sh
            ;;
        *)
            echo "You can run './up.sh' later to start Platform."
            ;;
    esac
else
    echo -e "\033[1;32mSetup complete! Run './up.sh' to start services.\033[0m"
fi

# Dev mode: offer to run local LiveKit on macOS
if [ "$DEV_MODE" == true ] && [[ "$(uname)" == "Darwin" ]]; then
    echo ""
    echo -e "\033[1;34mDev mode: Local LiveKit\033[0m"
    if command -v livekit-server &>/dev/null; then
        echo "LiveKit server found. Start it in a separate terminal:"
        echo -e "  \033[1;32m./dev/run-livekit.sh\033[0m"
    else
        echo "LiveKit server not installed. To enable audio/video calls:"
        echo -e "  \033[1;33mbrew install livekit\033[0m"
        echo "Then run:"
        echo -e "  \033[1;32m./dev/run-livekit.sh\033[0m"
    fi
fi
