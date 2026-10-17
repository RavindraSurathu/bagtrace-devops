#!/bin/bash
# App tier: install Python, deploy the API to /app and run it with systemd + gunicorn.
# Usage: sudo DB_HOST=mysql.example.internal DB_PASSWORD=... ./02-backend.sh

source "$(dirname "$0")/common.sh"
check_root

DB_HOST=${DB_HOST:?Set DB_HOST to the MySQL host}
DB_PASSWORD=${DB_PASSWORD:?Set DB_PASSWORD}
DB_USER=${DB_USER:-bagtrace}

dnf install python3.11 python3.11-pip -y &>>"$LOG_FILE"
VALIDATE $? "Installing Python 3.11"

app_user

rm -rf /app && mkdir -p /app
VALIDATE $? "Preparing /app"

cp "$REPO_DIR"/app/backend/{app.py,bsm.py,storage.py,wsgi.py,requirements.txt} /app/
VALIDATE $? "Copying application code"

python3.11 -m venv /app/venv &>>"$LOG_FILE"
VALIDATE $? "Creating virtualenv"

/app/venv/bin/pip install -r /app/requirements.txt &>>"$LOG_FILE"
VALIDATE $? "Installing Python dependencies"

# Database settings live in an env file readable only by root and the service.
cat > /etc/bagtrace.env <<EOF
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=bagtrace
EOF
chmod 640 /etc/bagtrace.env && chown root:bagtrace /etc/bagtrace.env
VALIDATE $? "Writing /etc/bagtrace.env"

chown -R bagtrace:bagtrace /app
cp "$SCRIPT_DIR/bagtrace-backend.service" /etc/systemd/system/
VALIDATE $? "Installing systemd unit"

if ! wait_for_port "$DB_HOST" 3306; then
    log "[WARN] ${Y}MySQL at $DB_HOST:3306 is not reachable yet; the service will keep retrying${N}"
fi

systemctl daemon-reload && systemctl enable bagtrace-backend &>>"$LOG_FILE" && systemctl restart bagtrace-backend
VALIDATE $? "Starting bagtrace-backend"

sleep 3
curl -sf http://127.0.0.1:8080/health/live &>>"$LOG_FILE"
VALIDATE $? "API answering on port 8080"

print_total_time
