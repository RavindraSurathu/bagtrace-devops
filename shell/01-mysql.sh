#!/bin/bash
# DB tier: install MySQL 8, secure it, create the app user and load the schema.
# Usage: sudo MYSQL_ROOT_PASSWORD=... DB_PASSWORD=... ./01-mysql.sh

source "$(dirname "$0")/common.sh"
check_root

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:?Set MYSQL_ROOT_PASSWORD}
DB_PASSWORD=${DB_PASSWORD:?Set DB_PASSWORD}
DB_USER=${DB_USER:-bagtrace}

dnf install mysql-server -y &>>"$LOG_FILE"
VALIDATE $? "Installing MySQL server"

systemctl enable --now mysqld &>>"$LOG_FILE"
VALIDATE $? "Enabling and starting mysqld"

# Set the root password only once: if it already works, skip.
if mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &>>"$LOG_FILE"; then
    skip "Root password already set"
else
    mysql_secure_installation --set-root-pass "$MYSQL_ROOT_PASSWORD" &>>"$LOG_FILE"
    VALIDATE $? "Setting MySQL root password"
fi

# Allow connections from the app tier (security groups restrict who can reach 3306).
if ! grep -q "^bind-address" /etc/my.cnf.d/mysql-server.cnf; then
    echo "bind-address = 0.0.0.0" >> /etc/my.cnf.d/mysql-server.cnf
    systemctl restart mysqld &>>"$LOG_FILE"
    VALIDATE $? "Listening on all interfaces"
fi

mysql -uroot -p"$MYSQL_ROOT_PASSWORD" &>>"$LOG_FILE" <<SQL
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
ALTER USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON bagtrace.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
SQL
VALIDATE $? "Creating application user $DB_USER"

mysql -uroot -p"$MYSQL_ROOT_PASSWORD" < "$REPO_DIR/app/db/schema.sql" &>>"$LOG_FILE"
VALIDATE $? "Loading BagTrace schema and sample data"

print_total_time
