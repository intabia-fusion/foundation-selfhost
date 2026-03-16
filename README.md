# Platform Self-Hosted

Please use this README if you want to deploy Platform on your server with `docker compose`.

## Docker based deployment

Install docker using the [recommended method](https://docs.docker.com/engine/install/ubuntu/) from docker website.
Afterwards perform [post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/). Pay attention to 3rd step with `newgrp docker` command, it needed for correct execution in setup script.

## Clone the `foundation-selfhost` repository and configure `nginx`

Next, let's clone the `foundation-selfhost` repository and configure Platform.

```bash
git clone https://github.com/intabiafusion/foundation-selfhost.git
cd foundation-selfhost
./setup.sh
```

This will generate a [platform_v7.conf](./platform_v7.conf) file with your chosen values and create your nginx config.

To add the generated configuration to your Nginx setup, run the following:

```bash
sudo ln -s $(pwd)/nginx.conf /etc/nginx/sites-enabled/huly.conf
```

> [!NOTE]
> If you change `HOST_ADDRESS`, `SECURE`, `HTTP_PORT` or `HTTP_BIND` be sure to update your [nginx.conf](./nginx.conf)
> by running:
>
> ```bash
> ./nginx.sh
> ```
>
> You can safely execute this script after adding your custom configurations like ssl. It will only overwrite the
> necessary settings.

Finally, let's reload `nginx` and start Platform with `docker compose`.

```bash
sudo nginx -s reload
sudo docker compose up -d
```

Now, launch your web browser and enjoy Platform!

> [!IMPORTANT]
> Provided configrations include deployments of CockroachDB and Redpanda which might not be production-ready.
> Please inspect them carefully before using in production. For more information on the recommended deployment configurations, please refer to the [CockroachDB](https://www.cockroachlabs.com/docs/stable/recommended-production-settings) and [Redpanda](https://docs.redpanda.com/24.3/deploy/) documentation.

> [!NOTE]
> **Mail Service**: The default configuration includes Mailpit for email debugging. All emails are captured at http://localhost:8025 but not delivered to real recipients. For production use, configure an external SMTP server or Amazon SES. See the [Mail Service](#mail-service) section below.

## Volume Configuration

By default, Platform uses Docker named volumes to store persistent data (database, Elasticsearch indices, and uploaded files).
You can optionally configure custom host paths for these volumes during the setup process.

### During Setup

When running `./setup.sh`, you'll be prompted to specify custom paths for:

- **Elasticsearch volume**: Search index data storage
- **Files volume**: User-uploaded files and attachments
- **CockroachDB data volume**: Data storage for workspaces and accounts
- **CockroachDB certs volume**: Certificates for CockroachDB
- **Redpanda data volume**: Data storage for Kafka

You can either:

- Press Enter to use the default Docker named volumes
- Specify an absolute path on your host system (e.g., `/var/huly/db`)
- Enter `default` to clear an existing custom path and revert to Docker named volumes

### Quick Reset to Default Volumes

To quickly reset all volumes back to default Docker named volumes without prompts:

```bash
./setup.sh --reset-volumes
```

### Manual Configuration

You can also manually configure volume paths by editing the `platform_v7.conf` file:

```bash
# Docker volume paths - specify custom paths for persistent data storage
# Leave empty to use default Docker named volumes
VOLUME_ELASTIC_PATH=/path/to/elasticsearch
VOLUME_FILES_PATH=/path/to/files
VOLUME_CR_DATA_PATH=/path/to/cockroachdb/data
VOLUME_CR_CERTS_PATH=/path/to/cockroachdb/certs
VOLUME_REDPANDA_PATH=/path/to/redpanda/data
```

To revert to default volumes, simply leave the paths empty:

```bash
VOLUME_ELASTIC_PATH=
VOLUME_FILES_PATH=
VOLUME_CR_DATA_PATH=
VOLUME_CR_CERTS_PATH=
VOLUME_REDPANDA_PATH=
```

After modifying the configuration, restart the services:

```bash
docker compose down
docker compose up -d
```

> [!WARNING]
> When changing from named volumes to host paths (or vice versa), make sure to migrate your data appropriately to avoid data loss.

## Redpanda Configuration

When using a production deployment of Redpanda with topics auto-creation turned off, you'll need to manually create the following topics:

- fulltext
- process
- tx
- users
- workspace

## Generating Public and Private VAPID keys for front-end

You'll need `Node.js` installed on your machine. Installing `npm` on Debian based distro:

```
sudo apt-get install npm
```

Install web-push using npm

```bash
sudo npm install -g web-push
```

Generate VAPID Keys. Run the following command to generate a VAPID key pair:

```
web-push generate-vapid-keys
```

It will generate both keys that looks like this:

```bash
=======================================

Public Key:
sdfgsdgsdfgsdfggsdf

Private Key:
asdfsadfasdfsfd

=======================================
```

Keep these keys secure, as you will need them to set up your push notification service on the server.

Add these keys into `compose.yaml` in section `services:ses:environment`:

```yaml
- PUSH_PUBLIC_KEY=your public key
- PUSH_PRIVATE_KEY=your private key
```

As the browser must access the public key for web push notifications setup, you also need to provide it to the front-end service.

Add the public key into `compose.yaml` in section `services:front:environment`:

```yaml
- PUSH_PUBLIC_KEY=your public key
```

## Web Push Notifications

> [!NOTE]
> In version 0.7.x and later, the `ses` service has been replaced with the `notification` service for web push notifications and the `mail` service for sending emails using SES. The environment variables `SECRET_KEY`, `PUSH_PUBLIC_KEY`, and `PUSH_PRIVATE_KEY` are not required for web push notifications in 0.7.x.

To enable web push notifications in Huly, you need to configure the SES service with the VAPID keys.

### Step 1: Configure the Transactor Service

Add `WEB_PUSH_URL` to `transactor` container:

```yaml
transactor:
  ...
  environment:
    - WEB_PUSH_URL=http://ses:3335
  ...
```

### Step 2: Configure the SES Service

Add the `ses` container to your `docker-compose.yaml` file with the generated VAPID keys:

```yaml
ses:
  image: intabiafusion/ses:${PLATFORM_VERSION}
  environment:
    - PORT=3335
    - SOURCE=mail@example.com
    - ACCESS_KEY=none
    - SECRET_KEY=none
    - PUSH_PUBLIC_KEY=${PUSH_PUBLIC_KEY}
    - PUSH_PRIVATE_KEY=${PUSH_PRIVATE_KEY}
  restart: unless-stopped
  networks:
    - huly_net
```

## Mail Service

The Mail Service is responsible for sending email notifications and confirmation emails during user login or signup processes. It can be configured to send emails through either an SMTP server or Amazon SES (Simple Email Service), but not both at the same time.

> [!IMPORTANT]
> **For normal operation, an SMTP server is required.** The default configuration includes Mailpit for debugging purposes, which captures all outgoing emails but does not deliver them to real recipients.

### Default Configuration (Mailpit for Debugging)

By default, the setup includes **Mailpit** - a lightweight SMTP server that captures all outgoing emails for debugging:

- **Mailpit Web UI**: http://localhost:8025 (view captured emails)
- **Mailpit SMTP**: localhost:1025 (receives emails from the application)
- **Mail Service**: http://localhost:8097 (Platform's mail API)

This configuration is useful for development and testing, but **emails are not delivered to real recipients**. For production use, configure an external SMTP server or Amazon SES.

### General Configuration

1. The default `compose.yml` already includes the mail infrastructure:
   - `mailpit` - SMTP server for capturing emails (port 8025 for UI, 1025 for SMTP)
   - `mail_server` - Platform mail server (port 8097)
   - `mail_client` - Platform mail client worker

2. To use your own SMTP server instead of Mailpit, update the `mail_server` environment variables in `compose.yml`:

   ```yaml
   mail_server:
     image: intabiafusion/mail:${PLATFORM_VERSION}
     environment:
       - MODE=queue
       - PORT=8097
       - SOURCE=hello@yourdomain.com
       - SMTP_HOST=smtp.yourdomain.com
       - SMTP_PORT=587
       - SMTP_USERNAME=your_smtp_user
       - SMTP_PASSWORD=your_smtp_password
       - SMTP_TLS_MODE=require
     ...
   ```

3. The mail URL is already configured in `transactor`, `account`, `workspace`, and `front` services via `MAIL_URL=http://mail_server:8097`.

4. In `Settings -> Notifications`, set up email notifications for the events you want to be notified about. Note that this is a user-specific setting, not company-wide; each user must set up their own notification preferences.

### SMTP Configuration (Replacing Mailpit)

To send emails to real recipients instead of capturing them in Mailpit, configure an external SMTP server:

1. Update the `mail_server` environment variables in `compose.yml`:

   ```yaml
   mail_server:
     ...
     environment:
       - MODE=queue
       - PORT=8097
       - SOURCE=noreply@yourdomain.com
       - SMTP_HOST=smtp.yourdomain.com
       - SMTP_PORT=587
       - SMTP_USERNAME=your_smtp_user
       - SMTP_PASSWORD=your_smtp_password
       - SMTP_TLS_MODE=require
   ```

2. Replace `smtp.yourdomain.com` and `587` with your SMTP server's hostname and port. Common ports:
   - `587` - SMTP with STARTTLS (recommended)
   - `465` - SMTPS (SMTP over SSL)
   - `25` - SMTP (often blocked by ISPs)

3. Replace `your_smtp_user` and `your_smtp_password` with your SMTP credentials. Consider using an application-specific password or API key for security.

4. You can optionally remove or disable the `mailpit` service if you no longer need it for debugging:

   ```yaml
   # Comment out or remove these services
   # mailpit:
   #   ...
   # mail_client:
   #   ...
   ```

   > [!NOTE]
   > Keep `mail_server` running as it's required for the Platform's mail API.

### Amazon SES Configuration

1. Set up Amazon Simple Email Service in AWS: [AWS SES Setup Guide](https://docs.aws.amazon.com/ses/latest/dg/setting-up.html)

2. Create a new IAM policy with the following permissions:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["ses:SendEmail", "ses:SendRawEmail"],
         "Resource": "*"
       }
     ]
   }
   ```

3. Create a separate IAM user for SES API access, assigning the newly created policy to this user.

4. Configure SES environment variables in the `mail` container:

   ```yaml
   mail:
     ...
     environment:
       ...
       - SES_ACCESS_KEY=<SES_ACCESS_KEY>
       - SES_SECRET_KEY=<SES_SECRET_KEY>
       - SES_REGION=<SES_REGION>
   ```

### Verifying Mail Service

To verify that the mail service is running correctly:

```bash
# Check if the mail containers are running
sudo docker ps | grep mail

# View mail service logs
sudo docker logs mail_server
sudo docker logs mail_client

# View Mailpit logs
sudo docker logs mailpit

# Follow mail service logs in real-time
sudo docker logs -f mail_server
```

### Accessing Mailpit Web Interface

When using the default Mailpit configuration, you can view captured emails:

1. Open http://localhost:8025 in your browser
2. All emails sent by the application will appear in the Mailpit inbox
3. Click on an email to view its contents, headers, and HTML/text versions
4. Use Mailpit's search and filtering features to find specific emails

This is useful for debugging email flows during development without sending real emails.

### Troubleshooting SMTP Issues

If you're experiencing issues with email delivery, see the [SMTP Troubleshooting Guide](guides/smtp-troubleshooting.md) for comprehensive debugging steps and solutions.

### Notes

1. SMTP and SES configurations cannot be used simultaneously.
2. `SES_URL` is not supported in version v0.6.470 and later, please use `MAIL_URL` instead.

## Gmail Integration

Huly supports Gmail integration allowing users to connect their Gmail accounts and manage emails directly within the platform.

For detailed setup instructions, see the [Gmail Configuration Guide](guides/gmail-configuration.md).

## Love Service (Audio & Video calls)

Huly audio and video calls are created on top of a LiveKit media server. The repository already contains the
`love`, `front`, and `livekit` services; you only need to provide credentials and networking.

1. Run `./setup.sh` and answer **Yes** when prompted about LiveKit. The helper can reuse an existing
   configuration or execute `docker run --rm -it -v "$PWD":/output livekit/generate --local` to mint a new
   API key and secret, update `livekit.yaml`, and inject the resulting values into `platform_v7.conf`.
2. When asked for the TURN domain, supply a DNS hostname that resolves to the same IP as your primary Huly domain.
   The script suggests `turn.<your-domain>` automatically, but you can override it if you prefer a different
   subdomain. Make sure you create DNS records for both the primary hostname and the TURN hostname, and open these
   ports on your firewall/router:

- `7880/tcp` – LiveKit HTTP/WebSocket API
- `7881/tcp` – TCP relay
- `5349/tcp` – TURN over TLS
- `5349/udp` – TURN over TLS (DTLS/UDP fallback)
- `3478/tcp` and `3478/udp` – TURN
- `50000-60000/udp` – media relay range

3. To present your own certificate on port `5349`, drop the PEM-encoded full-chain certificate and private key
   into `./certs/fullchain.pem` and `./certs/privkey.pem` respectively before starting Docker. Both the `nginx`
   and `livekit` services mount that directory (read-only), and the generated `livekit.yaml` already points the
   TURN settings at `/etc/livekit/certs/fullchain.pem` and `/etc/livekit/certs/privkey.pem`.
4. The `livekit` service now runs with `network_mode: host`. Ensure those ports are free on the host, lock down
   firewall rules so only trusted networks can reach them, and note that Redis is published on `6379` so LiveKit
   can talk to it via `127.0.0.1:6379`.
5. Start `docker compose up -d`. The compose file already propagates the `LIVEKIT_*` variables to both the
   `love` backend and the `front` web application, while the nginx templates expose `/livekit/` so clients can
   reach the server via `ws(s)://<your-domain>/livekit`.

## Print Service

1. Add `print` container to the docker-compose.yaml

   ```yaml
   print:
     image: intabiafusion/print:${PLATFORM_VERSION}
     container_name: print
     ports:
       - 4005:4005
     environment:
       - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
       - STATS_URL=http://stats:4900
       - SECRET=${SECRET}
     restart: unless-stopped
     networks:
       - huly_net
   ```

2. Configure `front` service:

   ```yaml
     front:
       ...
       environment:
         - PRINT_URL=http${SECURE:+s}://${HOST_ADDRESS}/_print
       ...
   ```

3. Uncomment print section in `.huly.nginx` file and reload nginx

## AI Service

Huly provides AI-powered chatbot that provides several services:

- chat with AI
- text message translations in the chat
- live translations for virtual office voice and video chats

1. Set up OpenAI account
2. Add `aibot` container to the docker-compose.yaml

   ```yaml
   aibot:
     image: intabiafusion/ai-bot:${PLATFORM_VERSION}
     ports:
       - 4010:4010
     environment:
       - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
       - SERVER_SECRET=${SECRET}
       - ACCOUNTS_URL=http://account:3000
       - DB_URL=${CR_DB_URL}
       - MONGO_URL=mongodb://mongodb:27017
       - STATS_URL=http://stats:4900
       - FIRST_NAME=Bot
       - LAST_NAME=Huly AI
       - PASSWORD=<PASSWORD>
       - OPENAI_API_KEY=<OPENAI_API_KEY>
       - OPENAI_BASE_URL=<OPENAI_BASE_URL>
       # optional if you use love service
       - LOVE_ENDPOINT=http://love:8096
     restart: unless-stopped
     networks:
       - huly_net
   ```

3. Configure `front` service:

   ```yaml
     front:
       ...
       environment:
         # this should be available outside of the cluster
         - AI_URL=http${SECURE:+s}://${HOST_ADDRESS}/_aibot
       ...
   ```

4. Configure `transactor` service:

   ```yaml
     transactor:
       ...
       environment:
         # this should be available inside of the cluster
         - AI_BOT_URL=http://aibot:4010
       ...
   ```

5. Uncomment aibot section in `.huly.nginx` file and reload nginx

## Configure Google Calendar Service

To integrate Google Calendar with Huly, follow these steps:

### Google side

1. Set up a Google Cloud project and enable the Google Calendar API in Google Cloud Console.
2. Create OAuth 2.0 credentials. Use `Web application` as the application type and `https://${HOST_ADDRESS}/_calendar/signin/code` (SET REAL VALUE INSTEAD OF ${HOST_ADDRESS}, https is required!!!) as Authorised redirect URIs. Save your credentials!
3. Add these scopes `./auth/calendar.calendarlist.readonly` `./auth/userinfo.email` `./auth/calendar.calendars.readonly` `./auth/calendar.events`

### Docker-compose side

Add `calendar` container to the docker-compose.yaml

```yaml
calendar:
  image: intabiafusion/calendar:${PLATFORM_VERSION}
  ports:
    - 8095:8095
  environment:
    - MONGO_URI=mongodb://mongodb:27017
    - MONGO_DB=%calendar-service
    - Credentials=<JSON_STRING_CREDENTIALS_FROM_GOOGLE_CONSOLE>
    - WATCH_URL=https://${HOST_ADDRESS}/_calendar/push
    - ACCOUNTS_URL=http://account:3000
    - STATS_URL=http://stats:4900
    - SECRET=${SECRET}
    - KVS_URL=http://kvs:8094
  restart: unless-stopped
  networks:
    - huly_net
```

## Configure OpenID Connect (OIDC)

You can configure a Huly instance to authorize users (sign-in/sign-up) using an OpenID Connect identity provider (IdP).

### On the IdP side

1. Create a new OpenID application.

   - Use `{huly_account_svc}/auth/openid/callback` as the sign-in redirect URI. The `huly_account_svc` is the hostname for the account service of the deployment, which should be accessible externally from the client/browser side. In the provided example setup, the account service runs on port 3000.

   **URI Example:**

   - `http://huly.mydomain.com:3000/auth/openid/callback`

2. Configure user access to the application as needed.

### On the Huly side

For the account service, set the following environment variables as provided by the IdP:

- OPENID_CLIENT_ID
- OPENID_CLIENT_SECRET
- OPENID_ISSUER

Ensure you have configured or add the following environment variable to the front service:

- ACCOUNTS_URL (This should contain the URL of the account service, accessible from the client side.)

You will need to expose your account service port (e.g. 3000) in your nginx.conf.

Note: Once all the required environment variables are configured, you will see an additional button on the
sign-in/sign-up pages.

## Configure GitHub OAuth

You can also configure a Huly instance to use GitHub OAuth for user authorization (sign-in/sign-up).

### On the GitHub side

1. Create a new GitHub OAuth application.

   - Use `{huly_account_svc}/_account/auth/github/callback` as the sign-in redirect URI. The `huly_account_svc` is the hostname for the account service of the deployment, which should be accessible externally from the client/browser side.

   **URI Example:**

   - `http://huly.mydomain.com/_account/auth/github/callback`

### On the Huly side

Specify the following environment variables for the account service:

- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

Ensure you have configured or add the following environment variable to the front service:

- `ACCOUNTS_URL` (The URL of the account service, accessible from the client side.)

Notes:

- The `ISSUER` environment variable is not required for GitHub OAuth.
- Once all the required environment variables are configured, you will see an additional button on the sign-in/sign-up
  pages.

## Disable Sign-Up

You can disable public sign-ups for a deployment. When configured, sign-ups will only be permitted through an invite
link to a specific workspace.

To implement this, set the following environment variable for both the front and account services:

```yaml
account:
  # ...
  environment:
    - DISABLE_SIGNUP=true
  # ...
front:
  # ...
  environment:
    - DISABLE_SIGNUP=true
  # ...
```

_Note: When setting up a new deployment, either create the initial account before disabling sign-ups or use the
development tool to create the first account._

## GitHub Service

Huly provides GitHub integration for bi-directional synchronization of issues, pull requests, comments, and reviews.

### Prerequisites

Set up a GitHub Application for your deployment.
Please refer to [GitHub Apps documentation](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) for full instructions on how to register your app.

During registration of the GitHub app, the following secrets should be obtained:

- `GITHUB_APPID` - An application ID number (e.g., 123456), which can be found in General/About in the GitHub UI.
- `GITHUB_CLIENTID` - A client ID, an identifier from the same page (e.g., Iv1.11a1aaa11aa11111).
- `GITHUB_CLIENT_SECRET` - A client secret that can be generated in the client secrets section of the General GitHub App UI page.
- `GITHUB_PRIVATE_KEY` - A private key for authentication.

### Configure Permissions

Set the following permissions for the app:

- Commit statuses: _Read and write_
- Contents: _Read and write_
- Custom properties: _Read and write_
- Discussions: _Read and write_
- Issues: _Read and write_
- Metadata: _Read-only_
- Pages: _Read and write_
- Projects: _Read and write_
- Pull requests: _Read and write_
- Webhooks: _Read and write_

### Subscribe to Events

Enable the following event subscriptions:

- Issues
- Pull request
- Pull request review
- Pull request review comment
- Pull request review thread

### Docker Configuration

1. Add the `github` container to the docker-compose.yaml

```yaml
github:
  image: intabiafusion/github:${PLATFORM_VERSION}
  ports:
    - 3500:3500
  environment:
    - PORT=3500
    - STORAGE_CONFIG=minio|minio?accessKey=minioadmin&secretKey=minioadmin
    - SERVER_SECRET=${SECRET}
    - ACCOUNTS_URL=http://account:3000
    - STATS_URL=http://stats:4900
    - APP_ID=${GITHUB_APPID}
    - CLIENT_ID=${GITHUB_CLIENTID}
    - CLIENT_SECRET=${GITHUB_CLIENT_SECRET}
    - PRIVATE_KEY=${GITHUB_PRIVATE_KEY}
    - COLLABORATOR_URL=ws${SECURE:+s}://${HOST_ADDRESS}/_collaborator
    - WEBHOOK_SECRET=secret
    - FRONT_URL=http${SECURE:+s}://${HOST_ADDRESS}
    - BOT_NAME=${yourAppName}[bot]
  restart: unless-stopped
  networks:
    - huly_net
```

2. Configure the `front` service:

```yaml
  front:
   ...
   environment:
    # this should be available outside of the cluster
    - GITHUB_APP=${GITHUB_APPID}
    - GITHUB_CLIENTID=${GITHUB_CLIENTID}
   ...
```

3. Uncomment the github section in `.huly.nginx` file and reload nginx

4. Configure Callback URL and Setup URL (with redirect on update set) to your host: `http${SECURE:+s}://${HOST_ADDRESS}/github`

5. Configure Webhook URL to `http${SECURE:+s}://${HOST_ADDRESS}/_github` with the secret `secret`
