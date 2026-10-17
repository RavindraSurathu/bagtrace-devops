#!/bin/bash
# shellcheck disable=SC2034  # variables here are used by the scripts that source this file
# Shared helpers for the BagTrace install scripts (RHEL 9 / Amazon Linux 2023).
# Each component script sources this file, then calls check_root.

LOGS_FOLDER="/var/log/bagtrace"
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
START_TIME=$(date +%s)

R="\e[31m"; G="\e[32m"; Y="\e[33m"; N="\e[0m"

mkdir -p "$LOGS_FOLDER"

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${R}ERROR:${N} run this script with root access (sudo $0)"
        exit 1
    fi
    log "[INFO] $SCRIPT_NAME started, logging to $LOG_FILE"
}

# VALIDATE <exit-code> <description>: stop the script on the first failure.
VALIDATE() {
    if [ "$1" -ne 0 ]; then
        log "[ERROR] $2 ... ${R}FAILURE${N} (see $LOG_FILE)"
        exit 1
    fi
    log "[INFO] $2 ... ${G}SUCCESS${N}"
}

skip() {
    log "[INFO] $1 ... ${Y}SKIPPING${N}"
}

# Create the non-login system user that owns and runs the application.
app_user() {
    if id bagtrace &>>"$LOG_FILE"; then
        skip "System user bagtrace already exists"
    else
        useradd --system --home /app --shell /sbin/nologin --comment "BagTrace service user" bagtrace &>>"$LOG_FILE"
        VALIDATE $? "Creating system user bagtrace"
    fi
}

# Wait until host:port accepts TCP connections (used to wait for MySQL).
wait_for_port() {
    local host=$1 port=$2 tries=${3:-30}
    for _ in $(seq "$tries"); do
        if timeout 2 bash -c "</dev/tcp/$host/$port" &>/dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}

print_total_time() {
    log "[INFO] $SCRIPT_NAME finished in ${G}$(( $(date +%s) - START_TIME )) seconds${N}"
}
