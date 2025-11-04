#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Honeypod Dynamic Compose Generator for OpenCanary
# Author: Farooq
# Usage:
#   sudo ./honetpod-start.sh -s ssh -p 24
#   sudo ./honetpod-start.sh -s ftp
# ==========================================================

SERVICE=""
HOST_PORT=""
IMAGE_NAME="honeypod:v1"
CONFIG_DIR="/opt/docker/opencanary/config"
COMPOSE_DIR="/opt/docker/opencanary/docker-compose"
LOG_BASE="/var/log/honeypod"

usage() {
  echo "Usage: $0 -s <service_name> [-p <host_port>]"
  echo "Example: $0 -s ssh -p 24"
  echo "         $0 -s ftp"
  exit 1
}

while getopts ":s:p:h" opt; do
  case $opt in
    s) SERVICE="$OPTARG" ;;
    p) HOST_PORT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$SERVICE" ]]; then
  echo "[!] Missing required argument: -s <service_name>"
  usage
fi

CONFIG_FILE="${CONFIG_DIR}/${SERVICE}.conf"
COMPOSE_FILE="${COMPOSE_DIR}/${SERVICE}-compose.yml"
LOG_DIR="${LOG_BASE}/${SERVICE}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[!] Config file not found: $CONFIG_FILE"
  echo "Available configs:"
  ls -1 "$CONFIG_DIR" | sed 's/^/   - /'
  exit 2
fi

mkdir -p "$LOG_DIR" "$COMPOSE_DIR"

# Default ports for OpenCanary services
declare -A DEFAULT_PORTS=(
  [citrix]=443
  [elastic]=9200
  [ftp]=21
  [git]=9418
  [http]=80
  [mssql]=1433
  [mysql]=3306
  [rdp]=3389
  [redis]=6379
  [sip]=5060
  [snmp]=161
  [ssh]=2222
  [telnet]=23
  [tftp]=69
  [vnc]=5900
)

# Extract container port from config or use default
CONTAINER_PORT=$(grep -Eo '"'"$SERVICE"'\.port" *: *[0-9]+' "$CONFIG_FILE" | grep -Eo '[0-9]+' || true)
if [[ -z "$CONTAINER_PORT" && -n "${DEFAULT_PORTS[$SERVICE]:-}" ]]; then
  CONTAINER_PORT="${DEFAULT_PORTS[$SERVICE]}"
elif [[ -z "$CONTAINER_PORT" ]]; then
  echo "[!] Could not detect container port. Using fallback 2222."
  CONTAINER_PORT=2222
fi

# If host port not provided, use same as container
if [[ -z "$HOST_PORT" ]]; then
  HOST_PORT="$CONTAINER_PORT"
  echo "[i] Host port not provided. Using default $HOST_PORT for $SERVICE."
fi

# Warn if port in use
if ss -ltn "( sport = :$HOST_PORT )" 2>/dev/null | grep -q LISTEN; then
  echo "[!] Warning: Host port $HOST_PORT is already in use. Container may fail to bind."
fi

echo "--------------------------------------------------"
echo "[+] Service       : $SERVICE"
echo "[+] Config file   : $CONFIG_FILE"
echo "[+] Container port: $CONTAINER_PORT"
echo "[+] Host port     : $HOST_PORT"
echo "[+] Logs directory: $LOG_DIR"
echo "[+] Compose file  : $COMPOSE_FILE"
echo "--------------------------------------------------"

# If container already exists, stop and remove it first
if docker ps -a --format '{{.Names}}' | grep -q "honeypod-${SERVICE}"; then
  echo "[*] Existing honeypod-${SERVICE} container found. Stopping and removing..."
  docker compose -f "$COMPOSE_FILE" down >/dev/null 2>&1 || true
  docker rm -f "honeypod-${SERVICE}" >/dev/null 2>&1 || true
fi

# Always replace existing compose file
echo "[*] Creating fresh compose file..."
cat > "$COMPOSE_FILE" <<EOF
# 🐝 Honeypod ${SERVICE^} Docker Compose File
version: '3.8'

services:
  ${SERVICE}:
    image: ${IMAGE_NAME}
    container_name: honeypod-${SERVICE}
    restart: unless-stopped
    user: root
    network_mode: bridge
    volumes:
      - ${CONFIG_FILE}:/etc/opencanaryd/opencanary.conf:ro
      - ${LOG_DIR}:/var/log
    ports:
      - "${HOST_PORT}:${CONTAINER_PORT}"
EOF

chmod 644 "$COMPOSE_FILE"

echo "[✓] Compose file replaced: $COMPOSE_FILE"

# Start container automatically
echo "[*] Launching honeypod container..."
docker compose -f "$COMPOSE_FILE" up -d >/dev/null

# Verify container is running
if docker ps --format '{{.Names}}' | grep -q "honeypod-${SERVICE}"; then
  echo "[✓] Honeypod '${SERVICE}' is now running on host port ${HOST_PORT}"
  echo "[→] Logs directory: ${LOG_DIR}"
else
  echo "[✗] Failed to start honeypod '${SERVICE}'. Check logs using:"
  echo "    docker logs honeypod-${SERVICE}"
fi
