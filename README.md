# Intabia Platform Self-Hosted

**English** | [Русский](README.ru.md)

Deploy Intabia Platform on your server with `docker compose`.

## Quick Start

### Prerequisites

- Operating system: **Linux or macOS**. The setup and helper scripts are Bash scripts and require a Unix shell. On Windows use WSL2 (Ubuntu).
- Docker: [Install guide](https://docs.docker.com/engine/install/ubuntu/), then [post-install steps](https://docs.docker.com/engine/install/linux-postinstall/)
- Nginx (for reverse proxy)
- Node.js (only for the Huly backup import tool, `import-backup.mjs`)

### Setup

```bash
git clone https://github.com/intabia-fusion/platform-selfhost.git
cd platform-selfhost
./setup.sh
```

The setup script will:
- Fetch the latest platform version from GitHub
- Prompt for host address, port, SSL, LiveKit, and volume configuration
- Generate `config/platform.conf` with all settings
- Generate secrets (only on first run — never overwritten)
- Create nginx configuration

### Start Services

```bash
./up.sh
```

> [!NOTE]
> The platform listens on **port 80** by default and is reachable directly at
> `http://<host>`. If you set a different `--port` (e.g. `8080`), you must put
> your own reverse proxy in front of it - the bundled nginx maps the chosen host
> port straight to the container, nothing else serves port 80.

### Stop Services

```bash
./down.sh          # Stop services (keep data)
./cleanup.sh       # Stop services (keep data)
./cleanup.sh --all # Full reset: remove config, secrets, and data
```

## Setup Options

```
./setup.sh [OPTIONS]

  --silent              Non-interactive mode (use defaults or provided values)
  --dev                 Development mode (localhost, LiveKit with devkey, no SSL)
  --host <address>      Host address (e.g., localhost or platform.example.com)
  --port <port>         HTTP port (default: 80)
  --ssl                 Enable SSL/HTTPS
  --ssl-cert <path>     Path to SSL certificate (fullchain.pem), copied to config/certs/
  --ssl-key <path>      Path to SSL private key (privkey.pem), copied to config/certs/
  --use-livekit         Enable LiveKit for audio/video calls
  --livekit-host <url>  LiveKit server URL (default: ws://<host>/livekit)
  --version <ver>       Platform version (e.g., v0.8.0). Fetches latest from GitHub if not set
  --push-public-key <k> VAPID public key for web push notifications
  --push-private-key <k> VAPID private key for web push notifications
  --llm <mode>          AI Bot model: local, openai, gigachat, none
  --llm-url <u>         LLM base URL (local models: http://host.docker.internal:1234/v1/)
  --llm-key <k>         LLM API key
  --llm-model <m>       Model name (also applied to summary and translate models)
  --gigachat-id <id>    GigaChat client id
  --gigachat-secret <s> GigaChat client secret
  --stt <mode>          Transcription: local, openai, none
  --stt-url <url>       Transcription endpoint
  --stt-key <k>         Transcription API key
  --stt-model <m>       Transcription model name
  --reset-volumes       Reset volume paths to Docker named volumes
```

See [AI Bot](#ai-bot) for LLM and transcription configuration.

## CI/CD Deployment

### Scenario 1: Update — Deploy New Version (Keep Data)

Use this when updating dev machines to a new platform version without losing data.

```bash
#!/bin/bash
# CI: Update devp1.intabia.ru to a new version
set -e

cd /path/to/platform-selfhost
git pull

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.8.0 \
  --use-livekit

./up.sh --pull --recreate
```

What this does:
- Updates config with the specified version and settings
- LiveKit defaults to `wss://devp1.intabia.ru/livekit` (proxied by the generated nginx config)
- Keeps existing data (Postgres, Elasticsearch, Redpanda, Minio)
- Keeps existing secrets (never regenerated if files exist)
- VAPID keys for web push generated automatically on first run
- Pulls new Docker images and recreates containers

### Scenario 2: Clean Deploy — Fresh Installation

Use this for setting up a new machine or full reset.

```bash
#!/bin/bash
# CI: Clean deploy devp1.intabia.ru from scratch
set -e

cd /path/to/platform-selfhost
git pull

# Full cleanup (removes config, secrets, data, volumes, images)
./cleanup.sh --all || true

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.8.0 \
  --use-livekit

./up.sh --pull
```

What this does:
- Removes all existing config, secrets, data, and Docker resources
- Generates new secrets and VAPID keys
- LiveKit defaults to `wss://devp1.intabia.ru/livekit`
- Initializes fresh databases
- Pulls images and starts services

> **Note:** Replace `devp1` with the actual machine number (`devp2`, `devp3`, etc.). An SSL certificate for `devpN.intabia.ru` must be provisioned in advance.

### Key Differences

| | Update (Scenario 1) | Clean (Scenario 2) |
|---|---|---|
| Secrets | Kept (files exist) | New (files deleted by cleanup) |
| VAPID keys | Kept | New |
| Database | Preserved | Empty |
| Docker images | Pulled if `--pull` | Pulled |
| Containers | Recreated if `--recreate` | Created |
| Config | Regenerated from template | Generated fresh |

> **Note:** Secrets are generated only when their files don't exist (`config/.platform.secret`, `config/.postgres.secret`, `config/.rp.secret`). If data directories exist but secrets are missing, setup.sh will warn about potential mismatches.

## Development Mode

For local development on macOS:

```bash
./setup.sh --dev
./up.sh
# In a separate terminal:
./dev/run-livekit.sh
```

`--dev` only affects LiveKit:
- LiveKit runs locally with `devkey/secret` on port 7880 (not in Docker)
- Dev livekit configs copied to `config/`
- Everything else (host, port, SSL, volumes) is configured normally via prompts or flags

LiveKit installation on macOS: `brew install livekit`

## Configuration

All configuration lives in `config/`:

| File | Description |
|---|---|
| `config/platform.conf` | Main config (env vars for docker compose) |
| `config/version.txt` | Platform version |
| `config/branding.json` | Branding configuration |
| `config/region-config.yaml` | Region configuration |
| `config/config-aibot.yaml` | AI Bot model registry (generated by `./setup_aibot.sh`) |
| `plan-config.yaml` | Plans, storage packages and AI token packs (repo root, not `config/`) |
| `config/nginx.conf` | Nginx configuration |
| `config/livekit.yaml` | LiveKit server config (when enabled) |
| `config/livekit-egress-config.yaml` | LiveKit Egress config (when enabled) |
| `config/certs/` | SSL certificates (`fullchain.pem`, `privkey.pem`) |
| `config/.platform.secret` | Platform secret |
| `config/.postgres.secret` | PostgreSQL password |
| `config/.rp.secret` | Redpanda admin password |
| `config/.admin.secret` | Technical admin password (created on first backup import) |

### Secrets

Secrets are generated once and never overwritten. If you need to regenerate:

1. Stop services: `./down.sh`
2. Delete the specific secret file (e.g., `rm config/.platform.secret`)
3. Run `./setup.sh` again

> **Warning:** If you delete `config/.postgres.secret` or `config/.rp.secret` while data directories exist, the new secrets won't match the stored passwords. Either delete data too (`./cleanup.sh --all`) or manually update the password inside the running service.

## Volume Configuration

By default, data is stored in `./data/` subdirectories. During interactive setup you can:

- Press Enter for defaults (`./data/<service>`)
- Enter a custom absolute path
- Type `none` to use Docker named volumes

Reset all to Docker named volumes:

```bash
./setup.sh --reset-volumes
```

## Nginx

Setup generates `config/nginx.conf`. To activate it, link the configuration to nginx's sites-enabled directory:

```bash
sudo ln -s $(pwd)/config/nginx.conf /etc/nginx/sites-enabled/platform.conf
sudo nginx -s reload
```

Alternatively, use the `nginx.sh` script with the `--link` and `--reload` flags to automate this process.

### Updating nginx configuration

After changing `HOST_ADDRESS`, `SECURE`, `HTTP_PORT`, or `HTTP_BIND`, regenerate nginx config:

```bash
./nginx.sh
```

The script supports several options:

- `--ssl-cert <path>` – copy an SSL certificate to `config/certs/fullchain.pem` (for LiveKit) and update nginx configuration to use this path directly
- `--ssl-key <path>` – copy an SSL private key to `config/certs/privkey.pem` (for LiveKit) and update nginx configuration to use this path directly
- `--link` – create or update the symlink `/etc/nginx/sites-enabled/platform.conf`
- `--reload` – automatically run `sudo nginx -s reload` without prompting
- `--auto` – equivalent to `--link --reload`
- `--recreate` – regenerate `nginx.conf` from the template

When `--ssl-cert` and `--ssl-key` are provided, nginx will reference the original certificate files directly (e.g., Let's Encrypt paths). The files are also copied to `config/certs/` for LiveKit compatibility.

Example for CI/CD:

```bash
./nginx.sh --ssl-cert /etc/letsencrypt/live/platform-dev1.intabia.ru/fullchain.pem \
           --ssl-key /etc/letsencrypt/live/platform-dev1.intabia.ru/privkey.pem \
           --auto
```

This updates the configuration, copies the certificates (for LiveKit), creates the symlink, and reloads nginx in one step.

## Web Push Notifications

VAPID keys for browser push notifications are **generated automatically** during `./setup.sh` (via a Docker container with `web-push`). No manual steps needed.

Keys are saved in `config/platform.conf` and reused on subsequent runs.

To provide your own keys instead:

```bash
./setup.sh --push-public-key "BEl62i..." --push-private-key "IwMHkf..."
```

Or edit `config/platform.conf` directly and restart: `./up.sh --recreate`

## Mail Service

The default configuration includes **Mailpit** for email debugging:

- **Mailpit UI**: `http://<host>:8025` (configurable via `MAILPIT_HTTP_PORT` in `config/platform.conf`)
- **SMTP**: port 1025 (internal, for Intabia Platform services)

All emails are captured but **not delivered** to real recipients.

### Production SMTP

To send real emails, update `mail_server` environment in `compose.yml`:

```yaml
mail_server:
  environment:
    - MODE=queue
    - SOURCE=noreply@yourdomain.com
    - SMTP_HOST=smtp.yourdomain.com
    - SMTP_PORT=587
    - SMTP_USERNAME=your_smtp_user
    - SMTP_PASSWORD=your_smtp_password
    - SMTP_TLS_MODE=require
```

### Amazon SES

See [AWS SES Setup Guide](https://docs.aws.amazon.com/ses/latest/dg/setting-up.html). Configure:

```yaml
mail:
  environment:
    - SES_ACCESS_KEY=<key>
    - SES_SECRET_KEY=<secret>
    - SES_REGION=<region>
```

> SMTP and SES cannot be used simultaneously.

## LiveKit (Audio & Video Calls)

### Production

Run `./setup.sh` and enable LiveKit when prompted (or use `--use-livekit`).

Required firewall ports:
- `7880/tcp` – LiveKit HTTP/WebSocket API
- `7881/tcp` – TCP relay
- `5349/tcp+udp` – TURN over TLS
- `3478/tcp+udp` – TURN
- `50000-60000/udp` – Media relay

SSL certificates are copied to `config/certs/fullchain.pem` and `config/certs/privkey.pem` (when using `--ssl-cert` / `--ssl-key`). LiveKit uses these copies; nginx can reference the original Let's Encrypt paths directly.

### Development

See [Development Mode](#development-mode). LiveKit runs locally, not in Docker.

## Other Services

### Print Service

Already included in `compose.yml`. Configure `front` service:

```yaml
front:
  environment:
    - PRINT_URL=http${SECURE:+s}://${HOST_ADDRESS}/_print
```

### AI Bot

Already included in `compose.yml`. Two independent parts: a language model (chat, summaries,
translation) and a transcription endpoint for meetings and voice notes. Both talk to any
OpenAI-compatible server, so local models work as well as cloud ones.

```bash
./setup_aibot.sh                # interactive
./up.sh --recreate              # apply
```

It asks two questions - which model and which transcription endpoint - and writes:

- `config/config-aibot.yaml` - the model registry the bot routes by (quality levels -> models)
- the AI values in `config/platform.conf` (keys, URLs, model names)

The yaml keeps `${VAR}` placeholders, so keys and model names can be changed in
`config/platform.conf` alone; regeneration is only needed to switch providers.
`./setup.sh` accepts the same options and forwards them.

#### Language model

| Mode | Meaning |
|---|---|
| `local` | OpenAI-compatible server on the Docker host - LM Studio, Ollama, vLLM, llama.cpp |
| `openai` | OpenAI cloud |
| `gigachat` | GigaChat cloud - three levels: Стандарт (GigaChat-2), Профи (-Pro), Максимум (-Max) |
| `none` | Do not write a model registry |

For a local model server on the Docker host use `http://host.docker.internal:<port>/v1/`
(`localhost` inside the container points at the container itself, not the host).

```bash
# Local LM Studio
./setup_aibot.sh --silent --llm local \
  --llm-url http://host.docker.internal:1234/v1/ --llm-model openai/gpt-oss-20b

# OpenAI cloud
./setup_aibot.sh --silent --llm openai --llm-key sk-... --llm-model gpt-4o-mini

# GigaChat cloud
./setup_aibot.sh --silent --llm gigachat --gigachat-id <client id> --gigachat-secret <client secret>
```

Levels, billing multipliers and context/answer caps live in `config/config-aibot.yaml` and can
be edited by hand - lower `maxContextTokens` / `maxOutputTokens` for a small local model.

#### Transcription

```bash
./setup_aibot.sh --silent --stt local --stt-url http://host.docker.internal:9007 --stt-model gigaam
```

`--stt` accepts `local`, `openai` (both are OpenAI-compatible `/v1/audio/transcriptions`
endpoints) or `none` to disable transcription.

The transcription server is **not** part of `compose.yml` - run it yourself, it is usually
GPU-bound and has its own lifecycle. A ready-made Russian-capable option is `oaitt`:

```bash
docker run -d --name oaitt --restart unless-stopped \
  -p 9007:9007 \
  -e PORT=9007 \
  -e ASR_ENGINE=gigaam \
  -e DEVICE=cpu \
  -e GIGAAM_MODEL=v3_e2e_ctc \
  intabiafusion/oaitt:v1.0.0
```

> The `oaitt` image is published for `linux/amd64` only; on Apple Silicon add `--platform linux/amd64`
> (runs under emulation and is slow). Use `DEVICE=cuda` on a GPU host.

Then point the platform at it:

```bash
./setup_aibot.sh --silent --stt local --stt-url http://host.docker.internal:9007 --stt-model gigaam
```

If the transcription server runs on another machine, use its address instead
(e.g. `--stt-url http://asr.internal:9007`).

### Payments and Plans

Plans, storage packages and AI token packs live in `plan-config.yaml` (mounted into the `payment`
service). The catalog drives the pricing page, the free tier and the "buy tokens" flow.

By default payments run on the **mock provider**: a purchase is activated instantly, no bank is
involved. Good for a self-hosted install where billing is a formality, and for testing the flow.

```
PAYMENT_PROVIDER=mock
FREE_PLAN_LIMITS={"usersLimit":25,"storagePerUserGB":40,"tokenLimit":1000000000,"windowMonthLimit":1000000000,"trafficLimitGB":0,"meetingMinutesLimit":0}
```

`FREE_PLAN_LIMITS` is what a workspace without an active subscription gets, and it must match the
plan marked `free: true` in `plan-config.yaml`. The defaults suit a self-hosted install: 25 users,
1 TB of disk (`usersLimit * storagePerUserGB`) and a billion AI tokens - enough for a team, or for
anyone who just wants to try the platform without hitting a paywall.

To exercise the real payment pipeline without a bank terminal, switch to T-Bank with its
in-process mock (issues payment links and fires its own CONFIRMED webhook):

```
PAYMENT_PROVIDER=tbank
TBANK_MOCK=true
```

`./up.sh` then also starts `tbank-subscriptions` (compose profile `tbank`). For a real terminal set
`TBANK_MOCK=false`, fill `TBANK_TERMINAL_KEY` / `TBANK_PASSWORD`, and expose the webhook endpoint by
uncommenting `location /_tbank_subscriptions` in `.platform.nginx`.

AI token packs are the `purchasables` block of `plan-config.yaml` (1M / 10M / 50M tokens). Bought
tokens land in a separate balance that does not expire at the end of the billing window and is
spent before the plan's own quota.

### Google Calendar

See [Gmail Configuration Guide](guides/gmail-configuration.md).

### OpenID Connect (OIDC)

Set in `account` service environment:
- `OPENID_CLIENT_ID`
- `OPENID_CLIENT_SECRET`
- `OPENID_ISSUER`

Redirect URI: `http${SECURE:+s}://${HOST_ADDRESS}/_accounts/auth/openid/callback`

### GitHub OAuth

Set in `account` service:
- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

Redirect URI: `http${SECURE:+s}://${HOST_ADDRESS}/_account/auth/github/callback`

### Disable Sign-Up

Set `DISABLE_SIGNUP=true` in both `account` and `front` services.

## Migrating from Huly Cloud

You can move a workspace from Huly cloud into this self-hosted instance: download
its backup and restore it locally.

The easiest way is the interactive wizard:

```bash
./import-from-huly.sh
```

It will ask, step by step, for just two things:

1. **Backup URL** and **token** - copy both from your Huly workspace under
   `Settings -> Backup -> Backup Files` (`Copy to clipboard` buttons).
2. **Workspace name** - any readable name for the new local workspace.

You do **not** create any user. The original users from the backup are recreated
automatically and assigned to the workspace.

> [!NOTE]
> Users sign in by email. In the demo setup the login code (OTP) is captured by
> **Mailpit** at `http://<host>:8025`. For production you must configure a real
> SMTP server (see [Production SMTP](#production-smtp)) so users receive OTP mail.
> A technical admin account (`admin@platform.local`) is created to bootstrap the
> workspace; its random password is stored in `config/.admin.secret`.

Downloads are cached under `backups/<huly-workspace-uuid>/` and reused on re-run.
Large media blobs are downloaded and uploaded into the local datalake too.

For manual steps, size limits, and troubleshooting see the import guide
([English](guides/backup-import.en.md) / [Русский](guides/backup-import.ru.md)).

## Useful Commands

```bash
./up.sh                    # Start services
./up.sh --pull             # Pull latest images and start
./up.sh --recreate         # Recreate containers
./up.sh --pull --recreate  # Pull + recreate (for updates)
./down.sh                  # Stop services
./cleanup.sh               # Stop services
./cleanup.sh --all         # Full reset
./set-version.sh v0.8.0  # Change platform version
./nginx.sh                 # Regenerate nginx config
```
