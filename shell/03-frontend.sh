#!/bin/bash
# Web tier: install Nginx, publish the dashboard and proxy /api to the app tier.
# Usage: sudo BACKEND_HOST=backend.example.internal ./03-frontend.sh

source "$(dirname "$0")/common.sh"
check_root

export BACKEND_HOST=${BACKEND_HOST:?Set BACKEND_HOST to the backend host}
export BACKEND_PORT=${BACKEND_PORT:-8080}

dnf install nginx gettext -y &>>"$LOG_FILE"
VALIDATE $? "Installing Nginx and envsubst"

rm -rf /usr/share/nginx/html/*
cp "$REPO_DIR"/app/frontend/{index.html,app.js,styles.css} /usr/share/nginx/html/
VALIDATE $? "Publishing dashboard files"

# Main config with no default server, then our site rendered from the shared template.
cp "$SCRIPT_DIR/nginx.conf" /etc/nginx/nginx.conf
envsubst '${BACKEND_HOST} ${BACKEND_PORT}' < "$REPO_DIR/app/frontend/nginx.conf.template" > /etc/nginx/conf.d/bagtrace.conf
VALIDATE $? "Rendering Nginx site for backend $BACKEND_HOST:$BACKEND_PORT"

nginx -t &>>"$LOG_FILE"
VALIDATE $? "Checking Nginx configuration"

# Let Nginx open outbound connections to the backend under SELinux.
if command -v setsebool &>/dev/null; then
    setsebool -P httpd_can_network_connect 1 &>>"$LOG_FILE"
    VALIDATE $? "Allowing Nginx network connections (SELinux)"
fi

systemctl enable nginx &>>"$LOG_FILE" && systemctl restart nginx
VALIDATE $? "Starting Nginx"

curl -sf http://127.0.0.1/nginx-health &>>"$LOG_FILE"
VALIDATE $? "Nginx answering on port 80"

print_total_time
