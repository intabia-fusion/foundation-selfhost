#!/usr/bin/env bash

# Generates the ai-bot model registry (config/config-aibot.yaml) and stores the answers
# in config/platform.conf. The yaml keeps ${VAR} placeholders, so keys, URLs and model
# names can be edited in platform.conf without regenerating it.

trap 'echo -e "\n\033[1;31mSetup interrupted. Exiting...\033[0m"; exit 130' INT TERM

CONFIG_DIR="config"
CONFIG_FILE="$CONFIG_DIR/platform.conf"
AIBOT_FILE="$CONFIG_DIR/config-aibot.yaml"

LOCAL_LLM_URL="http://host.docker.internal:1234/v1/"
LOCAL_LLM_MODEL="openai/gpt-oss-20b"
LOCAL_STT_URL="http://host.docker.internal:9007"
LOCAL_STT_MODEL="gigaam"
CLOUD_LLM_URL="https://api.openai.com/v1/"
CLOUD_LLM_MODEL="gpt-4o-mini"
CLOUD_STT_URL="https://api.openai.com/v1"
CLOUD_STT_MODEL="whisper-1"

SILENT=false

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configures the AI Bot (ЮляИИ) model registry for Intabia Platform.

Three ways to run the bot:
  local     any OpenAI-compatible server on the host (LM Studio, Ollama, vLLM, llama.cpp)
  openai    OpenAI cloud
  gigachat  GigaChat cloud (Стандарт / Профи / Максимум levels)

Transcription is a separate OpenAI-compatible endpoint (local or cloud).

OPTIONS:
  --silent               Regenerate config-aibot.yaml from the stored answers, no prompts
  --llm <mode>           local | openai | gigachat | none
  --llm-url <url>        LLM base URL (default local: $LOCAL_LLM_URL)
  --llm-key <k>          LLM API key
  --llm-model <m>        LLM model name (default local: $LOCAL_LLM_MODEL)
  --gigachat-id <id>     GigaChat client id
  --gigachat-secret <s>  GigaChat client secret
  --gigachat-key <k>     Ready-made authorization key (base64 "client_id:client_secret"),
                         alternative to --gigachat-id / --gigachat-secret
  --gigachat-scope <s>   GigaChat scope (default: GIGACHAT_API_PERS)
  --stt <mode>           local | openai | none
  --stt-url <url>        Transcription endpoint (default local: $LOCAL_STT_URL)
  --stt-key <k>          Transcription API key
  --stt-model <m>        Transcription model (default local: $LOCAL_STT_MODEL)
  --help                 Show this help message

EXAMPLES:
  $0                                    Interactive setup
  $0 --silent                           Regenerate the yaml from platform.conf
  $0 --llm local --stt local            Everything on the host, no cloud
  $0 --llm gigachat --gigachat-key <k> --stt local
  $0 --llm openai --llm-key sk-... --llm-model gpt-4o --stt openai --stt-key sk-...
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --silent) SILENT=true; shift ;;
        --llm) _CLI_LLM_MODE="$2"; shift 2 ;;
        --llm-url) _CLI_OPENAI_BASE_URL="$2"; shift 2 ;;
        --llm-key) _CLI_OPENAI_API_KEY="$2"; shift 2 ;;
        --llm-model) _CLI_OPENAI_MODEL="$2"; shift 2 ;;
        --gigachat-id) _CLI_GIGACHAT_CLIENT_ID="$2"; shift 2 ;;
        --gigachat-secret) _CLI_GIGACHAT_CLIENT_SECRET="$2"; shift 2 ;;
        --gigachat-key) _CLI_GIGACHAT_AUTH_KEY="$2"; shift 2 ;;
        --gigachat-scope) _CLI_GIGACHAT_SCOPE="$2"; shift 2 ;;
        --stt) _CLI_STT_MODE="$2"; shift 2 ;;
        --stt-url) _CLI_STT_URL="$2"; shift 2 ;;
        --stt-key) _CLI_STT_API_KEY="$2"; shift 2 ;;
        --stt-model) _CLI_STT_MODEL="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; echo "Use --help for usage information"; exit 1 ;;
    esac
done

mkdir -p "$CONFIG_DIR"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Rewrite a key in platform.conf (append when missing). sed -i differs between GNU and
# BSD, so the file is rewritten with awk instead.
set_conf() {
    local key="$1" value="$2"
    [[ -f "$CONFIG_FILE" ]] || return 0
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        awk -v k="$key" -v v="$value" '
            index($0, k "=") == 1 { print k "=" v; next }
            { print }
        ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# Result goes to $ANSWER: capturing read -p through $(...) would swallow the prompt.
ask() {
    local prompt="$1" current="$2"
    read -p "${prompt} [${current:-empty}]: " ANSWER
    ANSWER="${ANSWER:-$current}"
}

# CLI flag > platform.conf > default
_LLM_MODE="${_CLI_LLM_MODE:-${LLM_MODE:-local}}"
_STT_MODE="${_CLI_STT_MODE:-${STT_MODE:-local}}"
_OPENAI_API_KEY="${_CLI_OPENAI_API_KEY:-${OPENAI_API_KEY:-token}}"
_OPENAI_BASE_URL="${_CLI_OPENAI_BASE_URL:-${OPENAI_BASE_URL:-$LOCAL_LLM_URL}}"
_OPENAI_MODEL="${_CLI_OPENAI_MODEL:-${OPENAI_MODEL:-$LOCAL_LLM_MODEL}}"
_GIGACHAT_AUTH_KEY="${_CLI_GIGACHAT_AUTH_KEY:-${GIGACHAT_AUTH_KEY:-}}"
_GIGACHAT_SCOPE="${_CLI_GIGACHAT_SCOPE:-${GIGACHAT_SCOPE:-GIGACHAT_API_PERS}}"
_GIGACHAT_CLIENT_ID="${_CLI_GIGACHAT_CLIENT_ID:-${GIGACHAT_CLIENT_ID:-}}"

# GigaChat wants a single base64 "client_id:client_secret" authorization key. Users often
# paste that ready-made key into the secret field, so detect it instead of encoding it twice.
is_gigachat_key() {
    local decoded
    decoded=$(printf '%s' "$1" | base64 -d 2>/dev/null) || return 1
    [[ "$decoded" == *:* ]]
}
gigachat_key_from() {
    if is_gigachat_key "$2"; then
        printf '%s' "$2"
    else
        printf '%s:%s' "$1" "$2" | base64 | tr -d '\n'
    fi
}
if [[ -n "$_CLI_GIGACHAT_CLIENT_ID" && -n "$_CLI_GIGACHAT_CLIENT_SECRET" ]]; then
    _GIGACHAT_AUTH_KEY=$(gigachat_key_from "$_CLI_GIGACHAT_CLIENT_ID" "$_CLI_GIGACHAT_CLIENT_SECRET")
fi
_STT_URL="${_CLI_STT_URL:-${STT_URL:-$LOCAL_STT_URL}}"
_STT_API_KEY="${_CLI_STT_API_KEY:-${STT_API_KEY:-key}}"
_STT_MODEL="${_CLI_STT_MODEL:-${STT_MODEL:-$LOCAL_STT_MODEL}}"

# Switching modes on the command line without explicit url/model: use that mode's defaults.
if [[ -n "$_CLI_LLM_MODE" ]]; then
    case "$_CLI_LLM_MODE" in
        local)
            [[ -z "$_CLI_OPENAI_BASE_URL" ]] && _OPENAI_BASE_URL="$LOCAL_LLM_URL"
            [[ -z "$_CLI_OPENAI_MODEL" ]] && _OPENAI_MODEL="$LOCAL_LLM_MODEL"
            ;;
        openai)
            [[ -z "$_CLI_OPENAI_BASE_URL" ]] && _OPENAI_BASE_URL="$CLOUD_LLM_URL"
            [[ -z "$_CLI_OPENAI_MODEL" ]] && _OPENAI_MODEL="$CLOUD_LLM_MODEL"
            ;;
    esac
fi
if [[ -n "$_CLI_STT_MODE" ]]; then
    case "$_CLI_STT_MODE" in
        local)
            [[ -z "$_CLI_STT_URL" ]] && _STT_URL="$LOCAL_STT_URL"
            [[ -z "$_CLI_STT_MODEL" ]] && _STT_MODEL="$LOCAL_STT_MODEL"
            ;;
        openai)
            [[ -z "$_CLI_STT_URL" ]] && _STT_URL="$CLOUD_STT_URL"
            [[ -z "$_CLI_STT_MODEL" ]] && _STT_MODEL="$CLOUD_STT_MODEL"
            ;;
    esac
fi

if [ "$SILENT" == false ]; then
    echo -e "\n\033[1;34mAI Bot (ЮляИИ) - language model:\033[0m"
    echo "  1) local    - OpenAI-compatible server on this host (LM Studio, Ollama, vLLM)"
    echo "  2) openai   - OpenAI cloud"
    echo "  3) gigachat - GigaChat cloud (Стандарт / Профи / Максимум)"
    echo "  4) none     - do not configure a model"
    while true; do
        ask "Choose" "$_LLM_MODE"
        case "$ANSWER" in
            1|local) _LLM_MODE="local"; [[ "$_OPENAI_BASE_URL" == "$CLOUD_LLM_URL" ]] && { _OPENAI_BASE_URL="$LOCAL_LLM_URL"; _OPENAI_MODEL="$LOCAL_LLM_MODEL"; }; break ;;
            2|openai) _LLM_MODE="openai"; [[ "$_OPENAI_BASE_URL" == "$LOCAL_LLM_URL" ]] && { _OPENAI_BASE_URL="$CLOUD_LLM_URL"; _OPENAI_MODEL="$CLOUD_LLM_MODEL"; }; break ;;
            3|gigachat) _LLM_MODE="gigachat"; break ;;
            4|none) _LLM_MODE="none"; break ;;
            *) echo "Invalid choice." ;;
        esac
    done

    case "$_LLM_MODE" in
        local|openai)
            ask "  Base URL" "$_OPENAI_BASE_URL"; _OPENAI_BASE_URL="$ANSWER"
            ask "  API key" "$_OPENAI_API_KEY"; _OPENAI_API_KEY="$ANSWER"
            ask "  Model name" "$_OPENAI_MODEL"; _OPENAI_MODEL="$ANSWER"
            ;;
        gigachat)
            echo "  Credentials from the GigaChat API portal. Leave both empty to keep the current key."
            echo "  A ready-made authorization key can be pasted into the secret field instead."
            ask "  Client ID" "$_GIGACHAT_CLIENT_ID"; _GIGACHAT_CLIENT_ID="$ANSWER"
            ask "  Client Secret (or authorization key)" ""; _GIGACHAT_CLIENT_SECRET="$ANSWER"
            if [[ -n "$_GIGACHAT_CLIENT_SECRET" ]]; then
                _GIGACHAT_AUTH_KEY=$(gigachat_key_from "$_GIGACHAT_CLIENT_ID" "$_GIGACHAT_CLIENT_SECRET")
            elif [[ -z "$_GIGACHAT_AUTH_KEY" ]]; then
                ask "  Authorization key (base64 client_id:client_secret)" ""; _GIGACHAT_AUTH_KEY="$ANSWER"
            fi
            ask "  Scope" "$_GIGACHAT_SCOPE"; _GIGACHAT_SCOPE="$ANSWER"
            ;;
    esac

    echo -e "\n\033[1;34mTranscription (meetings, voice notes):\033[0m"
    echo "  1) local  - OpenAI-compatible transcription endpoint on this host"
    echo "  2) openai - OpenAI cloud"
    echo "  3) none   - disable transcription"
    while true; do
        ask "Choose" "$_STT_MODE"
        case "$ANSWER" in
            1|local) _STT_MODE="local"; [[ "$_STT_URL" == "$CLOUD_STT_URL" ]] && { _STT_URL="$LOCAL_STT_URL"; _STT_MODEL="$LOCAL_STT_MODEL"; }; break ;;
            2|openai) _STT_MODE="openai"; [[ "$_STT_URL" == "$LOCAL_STT_URL" ]] && { _STT_URL="$CLOUD_STT_URL"; _STT_MODEL="$CLOUD_STT_MODEL"; }; break ;;
            3|none) _STT_MODE="none"; break ;;
            *) echo "Invalid choice." ;;
        esac
    done

    if [[ "$_STT_MODE" != "none" ]]; then
        ask "  Endpoint" "$_STT_URL"; _STT_URL="$ANSWER"
        ask "  API key" "$_STT_API_KEY"; _STT_API_KEY="$ANSWER"
        ask "  Model name" "$_STT_MODEL"; _STT_MODEL="$ANSWER"
    fi
fi

# The key must decode to "client_id:client_secret"; a double-encoded one authenticates as garbage.
if [[ "$_LLM_MODE" == "gigachat" && -n "$_GIGACHAT_AUTH_KEY" ]]; then
    _DECODED=$(printf '%s' "$_GIGACHAT_AUTH_KEY" | base64 -d 2>/dev/null)
    if [[ "$_DECODED" != *:* ]]; then
        echo -e "\033[1;31mERROR: GigaChat authorization key does not decode to 'client_id:client_secret'.\033[0m"
        exit 1
    fi
    echo "  GigaChat key for client ${_DECODED%%:*}"
fi

# STT_PROVIDER stays an opt-out switch for the pod ('none' disables ASR entirely).
[[ "$_STT_MODE" == "none" ]] && _STT_PROVIDER="none" || _STT_PROVIDER="openai"
[[ "$_LLM_MODE" == "gigachat" ]] && _LLM_PROVIDER="gigachat" || _LLM_PROVIDER="openai"

set_conf LLM_MODE "$_LLM_MODE"
set_conf STT_MODE "$_STT_MODE"
set_conf LLM_PROVIDER "$_LLM_PROVIDER"
set_conf OPENAI_API_KEY "$_OPENAI_API_KEY"
set_conf OPENAI_BASE_URL "$_OPENAI_BASE_URL"
set_conf OPENAI_MODEL "$_OPENAI_MODEL"
set_conf OPENAI_SUMMARY_MODEL "$_OPENAI_MODEL"
set_conf OPENAI_TRANSLATE_MODEL "$_OPENAI_MODEL"
set_conf GIGACHAT_AUTH_KEY "$_GIGACHAT_AUTH_KEY"
set_conf GIGACHAT_SCOPE "$_GIGACHAT_SCOPE"
set_conf GIGACHAT_CLIENT_ID "$_GIGACHAT_CLIENT_ID"
set_conf STT_PROVIDER "$_STT_PROVIDER"
set_conf STT_URL "$_STT_URL"
set_conf STT_API_KEY "$_STT_API_KEY"
set_conf STT_MODEL "$_STT_MODEL"
set_conf AI_DEFAULT_LEVEL middle

# Docker creates a directory when a bind-mounted file is missing
[[ -d "$AIBOT_FILE" ]] && rm -rf "$AIBOT_FILE"

cat > "$AIBOT_FILE" <<'HEADER'
# ai-bot model registry, generated by ./setup_aibot.sh (mounted at /var/cfg/config.yaml).
# Reference: services/ai-bot/pod-ai-bot/config.example.yaml in the platform repo.
#
#   models:              level classes - UI/accounting metadata (label, order, multipliers)
#   providers[].serves:  level -> concrete model on that provider
#
# ${VAR} placeholders are expanded from the aibot container environment (config/platform.conf),
# so keys, URLs and model names can be changed there without regenerating this file.
HEADER

case "$_LLM_MODE" in
    local|openai)
        cat >> "$AIBOT_FILE" <<'LLMEOF'

llm:
  defaultLevel: middle

  models:
    middle:
      order: 10
      label: Стандарт
      tokenMultiplier: 1
      displayMultiplier: 1
      fallbackEligible: true

  providers:
    - id: openai
      provider: openai
      concurrency: 8
      batch: 1
      endpoint: "${OPENAI_BASE_URL}"
      endpointConfig:
        apiKey: "${OPENAI_API_KEY}"
      serves:
        middle:
          model: "${OPENAI_MODEL}"
          tokenizer: tiktoken
          # Context/answer caps. Lower them for a small local model.
          capabilities:
            maxContextTokens: 32768
            maxOutputTokens: 8192
LLMEOF
        ;;
    gigachat)
        cat >> "$AIBOT_FILE" <<'LLMEOF'

llm:
  defaultLevel: middle

  models:
    middle:
      order: 10
      label: Стандарт
      tokenMultiplier: 1.2
      displayMultiplier: 1
      fallbackEligible: true
    pro:
      order: 20
      label: Профи
      tokenMultiplier: 9.24
      displayMultiplier: 8
    max:
      order: 30
      label: Максимум
      tokenMultiplier: 12
      displayMultiplier: 10

  providers:
    - id: gigachat
      provider: gigachat
      concurrency: 2
      batch: 1
      endpoint: https://gigachat.devices.sberbank.ru/api/v1/
      endpointConfig:
        # base64 "client_id:client_secret", kept in config/platform.conf
        credentials: "${GIGACHAT_AUTH_KEY}"
        scope: "${GIGACHAT_SCOPE:-GIGACHAT_API_PERS}"
      serves:
        middle:
          model: GigaChat-2
          tokenizer: gigachat
          capabilities:
            maxContextTokens: 16384
            maxOutputTokens: 4096
        pro:
          model: GigaChat-2-Pro
          tokenizer: gigachat
          capabilities:
            maxContextTokens: 32768
            maxOutputTokens: 8192
        max:
          model: GigaChat-2-Max
          tokenizer: gigachat
          capabilities:
            maxContextTokens: 32768
            maxOutputTokens: 8192
LLMEOF
        ;;
esac

if [[ "$_STT_MODE" != "none" ]]; then
    cat >> "$AIBOT_FILE" <<'ASREOF'

# tokenMultiplier here bills per SECOND of audio, not per token.
asr:
  defaultLevel: default

  models:
    default:
      order: 0
      label: Базовый
      tokenMultiplier: 1
      displayMultiplier: 1

  providers:
    - id: openai
      provider: openai
      serves:
        default:
          model: "${STT_MODEL}"
          url: "${STT_URL}"
          apiKey: "${STT_API_KEY}"
ASREOF
fi

echo -e "\n\033[1;32mAI Bot configuration written to ${AIBOT_FILE}\033[0m"
case "$_LLM_MODE" in
    local|openai) echo "  Model: $_LLM_MODE - $_OPENAI_MODEL @ $_OPENAI_BASE_URL" ;;
    gigachat) echo "  Model: GigaChat-2 / -Pro / -Max${_GIGACHAT_AUTH_KEY:+ (auth key set)}" ;;
    none) echo "  Model: not configured" ;;
esac
if [[ "$_STT_MODE" == "none" ]]; then
    echo "  Transcription: disabled"
else
    echo "  Transcription: $_STT_MODE - $_STT_MODEL @ $_STT_URL"
fi
echo ""
echo "Apply with: ./up.sh --recreate"
