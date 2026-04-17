# Platform Self-Hosted

Deploy Platform on your server with `docker compose`.

## Quick Start

### Prerequisites

- Docker: [Install guide](https://docs.docker.com/engine/install/ubuntu/), then [post-install steps](https://docs.docker.com/engine/install/linux-postinstall/)
- Nginx (for reverse proxy)

### Setup

```bash
git clone https://github.com/intabiafusion/foundation-selfhost.git
cd foundation-selfhost
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
  --version <ver>       Platform version (e.g., v0.7.357). Fetches latest from GitHub if not set
  --push-public-key <k> VAPID public key for web push notifications
  --push-private-key <k> VAPID private key for web push notifications
  --reset-volumes       Reset volume paths to Docker named volumes
```

## CI/CD Deployment

### Scenario 1: Update — Deploy New Version (Keep Data)

Use this when updating dev machines to a new platform version without losing data.

```bash
#!/bin/bash
# CI: Update devp1.intabia.ru to a new version
set -e

cd /path/to/foundation-selfhost
git pull

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.7.357 \
  --use-livekit

./up.sh --pull --recreate
```

What this does:
- Updates config with the specified version and settings
- LiveKit defaults to `wss://lkit.devp1.intabia.ru` (auto-generated from host with SSL)
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

cd /path/to/foundation-selfhost
git pull

# Full cleanup (removes config, secrets, data, volumes, images)
./cleanup.sh --all || true

./setup.sh --silent \
  --host devp1.intabia.ru \
  --ssl \
  --ssl-cert /etc/letsencrypt/live/devp1.intabia.ru/fullchain.pem \
  --ssl-key /etc/letsencrypt/live/devp1.intabia.ru/privkey.pem \
  --version v0.7.357 \
  --use-livekit

./up.sh --pull
```

What this does:
- Removes all existing config, secrets, data, and Docker resources
- Generates new secrets and VAPID keys
- LiveKit defaults to `wss://lkit.devp1.intabia.ru`
- Initializes fresh databases
- Pulls images and starts services

> **Note:** Replace `devp1` with the actual machine number (`devp2`, `devp3`, etc.). SSL certificates for both `devpN.intabia.ru` and `lkit.devpN.intabia.ru` must be provisioned in advance.

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
| `config/nginx.conf` | Nginx configuration |
| `config/livekit.yaml` | LiveKit server config (when enabled) |
| `config/livekit-egress-config.yaml` | LiveKit Egress config (when enabled) |
| `config/certs/` | SSL certificates (`fullchain.pem`, `privkey.pem`) |
| `config/.platform.secret` | Platform secret |
| `config/.postgres.secret` | PostgreSQL password |
| `config/.rp.secret` | Redpanda admin password |

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
- **SMTP**: port 1025 (internal, for Platform services)

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

Already included in `compose.yml`. Requires OpenAI-compatible API. Configure in `config/platform.conf`:

```
OPENAI_API_KEY=your_key
OPENAI_BASE_URL=https://api.openai.com/v1/
OPENAI_SUMMARY_MODEL=gpt-4
OPENAI_TRANSLATE_MODEL=gpt-4
```

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

## Useful Commands

```bash
./up.sh                    # Start services
./up.sh --pull             # Pull latest images and start
./up.sh --recreate         # Recreate containers
./up.sh --pull --recreate  # Pull + recreate (for updates)
./down.sh                  # Stop services
./cleanup.sh               # Stop services
./cleanup.sh --all         # Full reset
./set-version.sh v0.7.400  # Change platform version
./nginx.sh                 # Regenerate nginx config
```
