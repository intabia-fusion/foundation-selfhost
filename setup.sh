#!/usr/bin/env bash
CONFIG_FILE="platform_v7.conf"

# Parse command line arguments
RESET_VOLUMES=false
SECRET=false

for arg in "$@"; do
    case $arg in
        --secret)
            SECRET=true
            ;;
        --reset-volumes)
            RESET_VOLUMES=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --secret         Generate a new secret key"
            echo "  --reset-volumes  Reset all volume paths to default Docker named volumes"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$RESET_VOLUMES" == true ]; then
    echo -e "\033[33m--reset-volumes flag detected: Resetting all volume paths to default Docker named volumes.\033[0m"
    sed -i \
        -e '/^VOLUME_ELASTIC_PATH=/s|=.*|=|' \
        -e '/^VOLUME_FILES_PATH=/s|=.*|=|' \
        -e '/^VOLUME_POSTGRES_DATA_PATH=/s|=.*|=|' \
        -e '/^VOLUME_REDPANDA_PATH=/s|=.*|=|' \
        "$CONFIG_FILE"
    exit 0
fi

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi
PREV_LIVEKIT_TURN_DOMAIN="${LIVEKIT_TURN_DOMAIN}"

RAW_HOST_INPUT=""

while true; do
    if [[ -n "$HOST_ADDRESS" ]]; then
        prompt_type="current"
        prompt_value="${HOST_ADDRESS}"
    else
        prompt_type="default"
        prompt_value="localhost"
    fi
    read -p "Enter the host address (domain name or IP) [${prompt_type}: ${prompt_value}]: " input
    RAW_HOST_INPUT="${input:-${HOST_ADDRESS:-localhost}}"
    _HOST_ADDRESS="$RAW_HOST_INPUT"
    break
done

while true; do
    if [[ -n "$HTTP_PORT" ]]; then
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
HOST_ONLY="${_HOST_ADDRESS%%:*}"

if [[ "$HOST_ONLY" == "localhost" || "$HOST_ONLY" == "127.0.0.1" || "$HOST_ONLY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    _HOST_ADDRESS="${HOST_ONLY}:${_HTTP_PORT}"
    SECURE=""
    _SECURE=""
else
    while true; do
        if [[ -n "$SECURE" ]]; then
            prompt_type="current"
            prompt_value="Yes"
        else
            prompt_type="default"
            prompt_value="No"
        fi
        read -p "Will you serve Huly over SSL? (y/n) [${prompt_type}: ${prompt_value}]: " input
        case "${input}" in
            [Yy]* )
                _SECURE="true"; break;;
            [Nn]* )
                _SECURE=""; break;;
            "" )
                _SECURE="${SECURE:+true}"; break;;
            * )
                echo "Invalid input. Please enter Y or N.";;
        esac
    done
fi

HOST_FOR_TURN="$HOST_ONLY"
HOST_FOR_TURN="${HOST_FOR_TURN:-$RAW_HOST_INPUT}"

HOST_PORT_VALUE=""
if [[ "$_HOST_ADDRESS" == *:* && "$_HOST_ADDRESS" != "$HOST_ONLY" ]]; then
    HOST_PORT_VALUE="${_HOST_ADDRESS##*:}"
fi

if [[ -n "$HOST_PORT_VALUE" ]]; then
    LIVEKIT_EXTERNAL_PORT="$HOST_PORT_VALUE"
elif [[ -n "$_SECURE" ]]; then
    LIVEKIT_EXTERNAL_PORT="443"
else
    LIVEKIT_EXTERNAL_PORT="$_HTTP_PORT"
fi

LIVEKIT_DEFAULT_CHOICE="n"
if [[ -n "$LIVEKIT_API_KEY" && -n "$LIVEKIT_API_SECRET" ]]; then
    LIVEKIT_DEFAULT_CHOICE="Y"
fi

_LIVEKIT_ENABLED=false
_LIVEKIT_API_KEY="$LIVEKIT_API_KEY"
_LIVEKIT_API_SECRET="$LIVEKIT_API_SECRET"

read -p "Enable LiveKit (audio & video calls)? (y/N) [default: ${LIVEKIT_DEFAULT_CHOICE}]: " input
case "$input" in
    [Yy]*)
        _LIVEKIT_ENABLED=true
        ;;
    "")
        if [[ "$LIVEKIT_DEFAULT_CHOICE" == "Y" ]]; then
            _LIVEKIT_ENABLED=true
        fi
        ;;
    *)
        _LIVEKIT_ENABLED=false
        ;;
esac

if [[ "$_LIVEKIT_ENABLED" == true ]]; then
    REUSE_PROMPT=1
    if [[ -z "$_LIVEKIT_API_KEY" || -z "$_LIVEKIT_API_SECRET" ]]; then
        REUSE_PROMPT=0
    fi

    REGENERATE_LIVEKIT=false
    if (( REUSE_PROMPT )); then
        read -p "Reuse existing LiveKit credentials? (Y/n): " reuse_answer
        case "$reuse_answer" in
            [Nn]*)
                REGENERATE_LIVEKIT=true
                ;;
            *)
                REGENERATE_LIVEKIT=false
                ;;
        esac
    else
        REGENERATE_LIVEKIT=true
    fi

    if [[ "$REGENERATE_LIVEKIT" == true ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            echo "Docker is required to generate LiveKit credentials automatically."
        else
            echo "Generating LiveKit credentials via livekit/generate..."
            if ! docker run --rm -it -v "$PWD":/output livekit/generate --local; then
                echo "LiveKit credential generation failed."
            fi
        fi
    fi

    if [[ -f livekit.yaml ]]; then
        LIVEKIT_KEYS_LINE=$(awk '/^keys:/ {getline; gsub(/^[[:space:]]+/, "", $0); print $0; exit}' livekit.yaml)
        if [[ -n "$LIVEKIT_KEYS_LINE" ]]; then
            _LIVEKIT_API_KEY=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f1 | tr -d '[:space:]')
            _LIVEKIT_API_SECRET=$(printf '%s' "$LIVEKIT_KEYS_LINE" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
        fi
    fi

    while [[ -z "$_LIVEKIT_API_KEY" ]]; do
        read -p "Enter LiveKit API Key: " _LIVEKIT_API_KEY
    done

    while [[ -z "$_LIVEKIT_API_SECRET" ]]; do
        read -s -p "Enter LiveKit API Secret: " secret_input
        echo
        if [[ -n "$secret_input" ]]; then
            _LIVEKIT_API_SECRET="$secret_input"
        fi
    done
    unset secret_input
else
    _LIVEKIT_API_KEY=""
    _LIVEKIT_API_SECRET=""
fi

# Volume path configuration
echo -e "\n\033[1;34mDocker Volume Configuration:\033[0m"

    echo "You can specify custom paths for persistent data storage, or leave empty to use default Docker named volumes."
    echo -e "\033[33mTip: To revert from custom paths to default volumes, enter 'default' or just press Enter when prompted.\033[0m"

    # Elasticsearch volume configuration
    if [[ -n "$VOLUME_ELASTIC_PATH" ]]; then
        current_elastic="custom: $VOLUME_ELASTIC_PATH"
    else
        current_elastic="default Docker volume"
    fi
    read -p "Enter custom path for Elasticsearch volume [current: ${current_elastic}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_ELASTIC_PATH=""
    else
        _VOLUME_ELASTIC_PATH="${input:-${VOLUME_ELASTIC_PATH}}"
    fi

    # Files volume configuration
    if [[ -n "$VOLUME_FILES_PATH" ]]; then
        current_files="custom: $VOLUME_FILES_PATH"
    else
        current_files="default Docker volume"
    fi
    read -p "Enter custom path for files volume [current: ${current_files}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_FILES_PATH=""
    else
        _VOLUME_FILES_PATH="${input:-${VOLUME_FILES_PATH}}"
    fi

    # PostgreSQL data volume configuration
    if [[ -n "$VOLUME_POSTGRES_DATA_PATH" ]]; then
        current_postgres_data="custom: $VOLUME_POSTGRES_DATA_PATH"
    else
        current_postgres_data="default Docker volume"
    fi
    read -p "Enter custom path for PostgreSQL data volume [current: ${current_postgres_data}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_POSTGRES_DATA_PATH=""
    else
        _VOLUME_POSTGRES_DATA_PATH="${input:-${VOLUME_POSTGRES_DATA_PATH}}"
    fi

    # Redpanda volume configuration
    if [[ -n "$VOLUME_REDPANDA_PATH" ]]; then
        current_redpanda="custom: $VOLUME_REDPANDA_PATH"
    else
        current_redpanda="default Docker volume"
    fi
    read -p "Enter custom path for Redpanda volume [current: ${current_redpanda}]: " input
    if [[ "$input" == "default" ]]; then
        _VOLUME_REDPANDA_PATH=""
    else
        _VOLUME_REDPANDA_PATH="${input:-${VOLUME_REDPANDA_PATH}}"
    fi

if [ ! -f .platform.secret ] || [ "$SECRET" == true ]; then
  openssl rand -hex 32 > .platform.secret
  echo "Secret generated and stored in .platform.secret"
else
  echo -e "\033[33m.platform.secret already exists, not overwriting."
  echo "Run this script with --secret to generate a new secret."
fi

if [ ! -f .postgres.secret ]; then
  openssl rand -hex 32 > .postgres.secret
  echo "Secret generated and stored in .postgres.secret"
fi

if [ ! -f .rp.secret ]; then
  openssl rand -hex 32 > .rp.secret
  echo "Secret generated and stored in .rp.secret"
fi

LIVEKIT_TURN_DOMAIN=""
_LIVEKIT_HOST=""
if [[ "$_LIVEKIT_ENABLED" == true ]]; then
    if [[ "$HOST_FOR_TURN" == "localhost" || "$HOST_FOR_TURN" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        DEFAULT_TURN_DOMAIN="$HOST_FOR_TURN"
    else
        DEFAULT_TURN_DOMAIN="turn.${HOST_FOR_TURN}"
    fi
    CURRENT_TURN_DOMAIN="${PREV_LIVEKIT_TURN_DOMAIN:-$DEFAULT_TURN_DOMAIN}"
    read -p "Enter TURN domain (DNS record pointing to this server) [${CURRENT_TURN_DOMAIN}]: " turn_input
    LIVEKIT_TURN_DOMAIN="${turn_input:-$CURRENT_TURN_DOMAIN}"
    unset turn_input

    LIVEKIT_BASE_HOST="$HOST_ONLY"
    if [[ -n "$_SECURE" ]]; then
        if [[ "$LIVEKIT_EXTERNAL_PORT" != "443" ]]; then
            LIVEKIT_BASE_HOST="${LIVEKIT_BASE_HOST}:${LIVEKIT_EXTERNAL_PORT}"
        fi
    else
        if [[ "$LIVEKIT_EXTERNAL_PORT" != "80" ]]; then
            LIVEKIT_BASE_HOST="${LIVEKIT_BASE_HOST}:${LIVEKIT_EXTERNAL_PORT}"
        fi
    fi

    if [[ -n "$_SECURE" ]]; then
        LIVEKIT_SCHEME="wss"
    else
        LIVEKIT_SCHEME="ws"
    fi

    _LIVEKIT_HOST="${LIVEKIT_SCHEME}://${LIVEKIT_BASE_HOST}/livekit"

    if [[ -f .template.livekit.yaml ]]; then
        export LIVEKIT_API_KEY="$_LIVEKIT_API_KEY"
        export LIVEKIT_API_SECRET="$_LIVEKIT_API_SECRET"
        export LIVEKIT_TURN_DOMAIN="$LIVEKIT_TURN_DOMAIN"
        envsubst < .template.livekit.yaml > livekit.yaml
        echo "LiveKit configuration updated at livekit.yaml"
    else
        echo "LiveKit template (.template.livekit.yaml) not found; skipping livekit.yaml generation."
    fi
else
    _LIVEKIT_API_KEY=""
    _LIVEKIT_API_SECRET=""
fi

export HOST_ADDRESS=$_HOST_ADDRESS
export SECURE=$_SECURE
export HTTP_PORT=$_HTTP_PORT
export HTTP_BIND=$HTTP_BIND
export TITLE=${TITLE:-Huly}
export DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-ru}
export LAST_NAME_FIRST=${LAST_NAME_FIRST:-true}
export POSTGRES_DB=${POSTGRES_DB:-platform}
export POSTGRES_USER=${POSTGRES_USER:-platform}
export REDPANDA_ADMIN_USER=${REDPANDA_ADMIN_USER:-superadmin}
# Ensure volume paths have ./ prefix for relative paths (required by Docker Compose)
if [[ -n "$_VOLUME_ELASTIC_PATH" && ! "$_VOLUME_ELASTIC_PATH" =~ ^(/|\./) ]]; then
    export VOLUME_ELASTIC_PATH="./$_VOLUME_ELASTIC_PATH"
else
    export VOLUME_ELASTIC_PATH=$_VOLUME_ELASTIC_PATH
fi
if [[ -n "$_VOLUME_FILES_PATH" && ! "$_VOLUME_FILES_PATH" =~ ^(/|\./) ]]; then
    export VOLUME_FILES_PATH="./$_VOLUME_FILES_PATH"
else
    export VOLUME_FILES_PATH=$_VOLUME_FILES_PATH
fi
if [[ -n "$_VOLUME_POSTGRES_DATA_PATH" && ! "$_VOLUME_POSTGRES_DATA_PATH" =~ ^(/|\./) ]]; then
    export VOLUME_POSTGRES_DATA_PATH="./$_VOLUME_POSTGRES_DATA_PATH"
else
    export VOLUME_POSTGRES_DATA_PATH=$_VOLUME_POSTGRES_DATA_PATH
fi
if [[ -n "$_VOLUME_REDPANDA_PATH" && ! "$_VOLUME_REDPANDA_PATH" =~ ^(/|\./) ]]; then
    export VOLUME_REDPANDA_PATH="./$_VOLUME_REDPANDA_PATH"
else
    export VOLUME_REDPANDA_PATH=$_VOLUME_REDPANDA_PATH
fi
export PLATFORM_SECRET=$(cat .platform.secret)
export POSTGRES_SECRET=$(cat .postgres.secret)
export REDPANDA_SECRET=$(cat .rp.secret)
export LIVEKIT_HOST=${_LIVEKIT_HOST}
export LIVEKIT_API_KEY=${_LIVEKIT_API_KEY}
export LIVEKIT_API_SECRET=${_LIVEKIT_API_SECRET}
export LIVEKIT_TURN_DOMAIN=${LIVEKIT_TURN_DOMAIN}
export LIVEKIT_ENABLED=${_LIVEKIT_ENABLED}
export STT_PROVIDER=${STT_PROVIDER:-openai}
export STT_URL=${STT_URL}
export STT_API_KEY=${STT_API_KEY}
export STT_MODEL=${STT_MODEL}
export OPENAI_API_KEY=${OPENAI_API_KEY:-token}
export OPENAI_BASE_URL=${OPENAI_BASE_URL:-http://localhost:1234/v1/}
export OPENAI_SUMMARY_MODEL=${OPENAI_SUMMARY_MODEL:-openai/gpt-oss-20b}
export OPENAI_TRANSLATE_MODEL=${OPENAI_TRANSLATE_MODEL:-openai/gpt-oss-20b}

envsubst < .template.platform.conf > $CONFIG_FILE

source "$CONFIG_FILE"
export CR_DB_URL=$CR_DB_URL

echo -e "\n\033[1;34mConfiguration Summary:\033[0m"
echo -e "Host Address: \033[1;32m$_HOST_ADDRESS\033[0m"
echo -e "HTTP Port: \033[1;32m$_HTTP_PORT\033[0m"
if [[ -n "$SECURE" ]]; then
    echo -e "SSL Enabled: \033[1;32mYes\033[0m"
else
    echo -e "SSL Enabled: \033[1;31mNo\033[0m"
fi
echo -e "Elasticsearch Volume: \033[1;32m${_VOLUME_ELASTIC_PATH:-Docker named volume}\033[0m"
echo -e "Files Volume: \033[1;32m${_VOLUME_FILES_PATH:-Docker named volume}\033[0m"
echo -e "PostgreSQL Volume: \033[1;32m${_VOLUME_POSTGRES_DATA_PATH:-Docker named volume}\033[0m"
echo -e "Redpanda Volume: \033[1;32m${_VOLUME_REDPANDA_PATH:-Docker named volume}\033[0m"
if [[ "$_LIVEKIT_ENABLED" == true ]]; then
    echo -e "LiveKit: \033[1;32mEnabled\033[0m (Endpoint: $_LIVEKIT_HOST, TURN host: ${LIVEKIT_TURN_DOMAIN})"
else
    echo -e "LiveKit: \033[1;31mDisabled\033[0m"
fi

read -p "Do you want to run 'docker compose up -d' now to start Huly? (Y/n): " RUN_DOCKER
case "${RUN_DOCKER:-Y}" in
    [Yy]* )
         echo -e "\033[1;32mRunning 'docker compose up -d' now...\033[0m"
         docker compose up -d
         ;;
    [Nn]* )
        echo "You can run 'docker compose up -d' later to start Huly."
        ;;
esac

echo -e "\033[1;32mSetup is complete!\n Generating nginx.conf...\033[0m"
./nginx.sh
