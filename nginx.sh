#!/bin/bash

if [ -f ".env" ]; then
    source ".env"
fi

if [ -z "$LIVEKIT_ENABLED" ] && [ -f "platform_v7.conf" ]; then
    source "platform_v7.conf"
fi

# Check for --recreate flag
RECREATE=false
if [ "$1" == "--recreate" ]; then
    RECREATE=true
fi

# Handle nginx.conf recreation or updating
TEMPLATE_FILE=".template.nginx.conf"
TEMPLATE_NAME="standard"
LIVEKIT_MARKER="# LiveKit proxy block"

if [[ "$LIVEKIT_ENABLED" == "true" ]]; then
    TEMPLATE_FILE=".template.nginx-livekit.conf"
    TEMPLATE_NAME="LiveKit"
fi

COPY_REASON=""
if [ "$RECREATE" == true ]; then
    COPY_REASON="recreate"
elif [ ! -f "nginx.conf" ]; then
    COPY_REASON="missing"
elif [[ "$LIVEKIT_ENABLED" == "true" ]]; then
    if ! grep -q "$LIVEKIT_MARKER" nginx.conf; then
        COPY_REASON="enable_livekit"
    fi
else
    if grep -q "$LIVEKIT_MARKER" nginx.conf; then
        COPY_REASON="disable_livekit"
    fi
fi

if [[ -n "$COPY_REASON" ]]; then
    cp "$TEMPLATE_FILE" nginx.conf
    case "$COPY_REASON" in
        recreate)
            echo "nginx.conf has been recreated from the ${TEMPLATE_NAME} template."
            ;;
        missing)
            echo "nginx.conf not found, created from the ${TEMPLATE_NAME} template."
            ;;
        enable_livekit)
            echo "Switched nginx.conf to the LiveKit-aware template."
            ;;
        disable_livekit)
            echo "Reverted nginx.conf to the standard template."
            ;;
    esac
else
    echo "nginx.conf already exists. Only updating server_name, listen, and proxy_pass."
    echo "Run with --recreate to fully overwrite nginx.conf."
fi

# Update server_name and proxy_pass
sed -i.bak "s|server_name .*;|server_name ${HOST_ADDRESS};|" ./nginx.conf

BACKEND_TARGET="http://${HTTP_BIND:-127.0.0.1}:${HTTP_PORT}"
awk -v backend="$BACKEND_TARGET" '
    BEGIN { done = 0 }
    {
        if (!done && $0 ~ /proxy_pass/ && $0 !~ /livekit/) {
            sub(/proxy_pass [^;]*;/, "proxy_pass " backend ";")
            done = 1
        }
        print
    }
' nginx.conf > nginx.conf.tmp && mv nginx.conf.tmp nginx.conf || echo "Warning: unable to update proxy_pass in nginx.conf"

# Update listen directive to either port 80 or 443, while preserving IP address
if [[ -n "$SECURE" ]]; then
    # Secure (use port 443 and add 'ssl')
    sed -i.bak -E 's|(listen )(.*:)?([0-9]+)?;|\1443 ssl;|' ./nginx.conf
    echo "Serving over SSL. Make sure to add your SSL certificates."
else
    # Non-secure (use port 80 and remove 'ssl')
    sed -i.bak -E "s|(listen )(.*:)?[0-9]+ ssl;|\1\280;|" ./nginx.conf
    sed -i.bak -E "s|(listen )(.*:)?([0-9]+)?;|\1\280;|" ./nginx.conf
fi

# Extract IP address for redirect configuration
IP_ADDRESS=$(grep -oE 'listen \K[^:]+(?=:[0-9]+ ssl;)' nginx.conf)

# Remove HTTP to HTTPS redirect server block if SSL is enabled
if [[ -z "$SECURE" ]]; then
    echo "SSL disabled; ensuring no HTTP to HTTPS redirect block remains..."
    # Remove the entire server block for port 80
    if grep -q 'return 301 https://\$host\$request_uri;' nginx.conf; then
        sed -i.bak '/# !/,/!/d' nginx.conf
    fi
else
    # Check if the HTTP to HTTPS redirect block already exists
    if grep -q 'return 301 https://\$host\$request_uri;' nginx.conf; then
        sed -i.bak '/# !/,/!/d' nginx.conf
    fi

    echo "Creating HTTP to HTTPS redirect..."
    echo -e "# ! DO NOT REMOVE COMMENT
# DO NOT MODIFY, CHANGES WILL BE OVERWRITTEN
server {
    listen ${IP_ADDRESS:+${IP_ADDRESS}:}80;
    server_name ${HOST_ADDRESS};
    return 301 https://\$host\$request_uri;
}
# DO NOT REMOVE COMMENT !" >> ./nginx.conf
fi

read -p "Do you want to run 'nginx -s reload' now to load your updated Huly config? (Y/n): " RUN_NGINX
case "${RUN_NGINX:-Y}" in  
    [Yy]* )  
        echo -e "\033[1;32mRunning 'nginx -s reload' now...\033[0m"
        sudo nginx -s reload
        ;;
    [Nn]* )
        echo "You can run 'nginx -s reload' later to load your updated Huly config."
        ;;
esac