#!/bin/bash
# 🐝 Honeypod Auto-Deploy Script (Advanced & Dynamic)
# Author: Paro | Version: v5.0 (2025 Update)
# Auto-download configs if missing

set -euo pipefail

CONFIG_DIR="/opt/docker/opencanary/config"
COMPOSE_DIR="/opt/docker/opencanary/docker-compose"
LOG_DIR="/var/log/honeypod"
IMAGE_NAME="baba001/honeypod:v1"

# Full service:port mapping
declare -A DEFAULT_PORTS=(
  [ssh]=2222
  [ftp]=21
  [http]=80
  [https]=443
  [mysql]=3306
  [mssql]=1433
  [redis]=6379
  [rdp]=3389
  [telnet]=23
  [tftp]=69
  [snmp]=161
  [citrix]=443
  [git]=9418
  [sip]=5060
  [vnc]=5900
  [smb]=445
  [smb-share]=445
  [elastic]=9200
  [ciscoasa]=2055
  [nmapscan]=8001
  [portscan]=9998
)

usage() {
  echo ""
  echo "🐝 Honeypod Advanced Deploy"
  echo "Usage:"
  echo "  $0 -s <service>[,<service>...] [-p <service:port>[,<service:port>...]] [-l <logdir>] [-c <configdir>] [--all] [-h]"
  echo "Examples:"
  echo "  $0 -s ssh -p ssh:24"
  echo "  $0 -s ftp"
  echo "  $0 --all"
  echo "Available services (default ports):"
  for k in "${!DEFAULT_PORTS[@]}"; do
    printf "  %s (%s)\n" "$k" "${DEFAULT_PORTS[$k]}"
  done
  exit 1
}

# Parse options
SERVICES=""
CUSTOM_LOG_DIR="$LOG_DIR"
CUSTOM_CONFIG_DIR="$CONFIG_DIR"
DO_ALL=0
declare -A SERVICE_PORTS

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--service)
      SERVICES="$2"; shift 2 ;;
    -p|--port)
      # Support multiple service-specific ports: ssh:2222,ftp:21
      IFS=',' read -ra PORT_PAIRS <<< "$2"
      for pair in "${PORT_PAIRS[@]}"; do
        svc="${pair%%:*}"
        port="${pair##*:}"
        SERVICE_PORTS[$svc]=$port
      done
      shift 2 ;;
    -l|--logdir)
      CUSTOM_LOG_DIR="$2"; shift 2 ;;
    -c|--configdir)
      CUSTOM_CONFIG_DIR="$2"; shift 2 ;;
    --all)
      DO_ALL=1; shift ;;
    -h|--help)
      usage ;;
    *)
      echo "[❌] Unknown option: $1"; usage ;;
  esac
done

if [[ $DO_ALL -eq 1 ]]; then
  SERVICES="$(IFS=,; echo "${!DEFAULT_PORTS[*]}")"
fi

[ -z "$SERVICES" ] && usage
IFS=',' read -ra SERVICE_LIST <<< "$SERVICES"

# Auto-detect docker compose
DOCKER_COMPOSE="docker compose"
if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
  if command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE="docker-compose"
  else
    echo "[❌] Docker Compose not found!"; exit 1
  fi
fi

for SERVICE in "${SERVICE_LIST[@]}"; do
  SERVICE=$(echo "$SERVICE" | tr '[:upper:]' '[:lower:]')
  CONF_FILE="${CUSTOM_CONFIG_DIR}/${SERVICE}.conf"
  LOG_PATH="${CUSTOM_LOG_DIR}/${SERVICE}"
  COMPOSE_FILE="${COMPOSE_DIR}/${SERVICE}-compose.yml"
  DEFAULT_PORT="${DEFAULT_PORTS[$SERVICE]:-9999}"
  PORT="${SERVICE_PORTS[$SERVICE]:-$DEFAULT_PORT}"

  # Ensure directories exist
  mkdir -p "$CUSTOM_CONFIG_DIR" "$LOG_PATH" "$COMPOSE_DIR"

  # Auto-download config if missing
  if [ ! -f "$CONF_FILE" ]; then
    echo "[⚡] Config for '$SERVICE' not found. Downloading default..."
    wget -q -O "$CONF_FILE" "https://raw.githubusercontent.com/farooq-001/Opencanar-Notes/master/docker/opencanary/config/${SERVICE}.conf" \
      && echo "[✅] Config downloaded: $CONF_FILE" \
      || { echo "[❌] Failed to download config for $SERVICE"; continue; }
  fi

  # Port validation
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "[❌] Invalid port ($PORT) for $SERVICE"
    continue
  fi

  # Compose YAML
  cat > "$COMPOSE_FILE" <<EOF
# 🐝 Honeypod $SERVICE
services:
  $SERVICE:
    image: $IMAGE_NAME
    container_name: honeypod-$SERVICE
    restart: unless-stopped
    user: root
    network_mode: bridge
    volumes:
      - $CONF_FILE:/etc/opencanaryd/opencanary.conf:ro
      - $LOG_PATH:/var/log
    ports:
      - "${PORT}:${DEFAULT_PORT}"
EOF

  echo -e "\033[1;34m[+] Compose file for $SERVICE:\033[0m $COMPOSE_FILE"
  echo -e "\033[1;34m[+] Starting $SERVICE on $PORT with $CONF_FILE...\033[0m"
  $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d

  sleep 1

  # Banner injection
  inject_banner() {
    local SERVICE_NAME="${1^^}"
    local CONTAINER_NAME="honeypod-${1}"
    local CONTAINER_ID=$(docker ps -aqf "name=${CONTAINER_NAME}" | head -n 1)
    [ -z "$CONTAINER_ID" ] && echo "[⚠️] Missing container for $SERVICE_NAME" && return
    local SHORT_ID=$(docker ps --filter "id=${CONTAINER_ID}" --format "{{.ID}}" | cut -c1-12)
    local BANNER_SCRIPT="/root/banner.sh"
    docker exec -i "$CONTAINER_NAME" bash -c "cat > ${BANNER_SCRIPT}" <<EOF
#!/bin/bash
command -v clear &>/dev/null && clear
LINE_WIDTH=47
TEXT="🐝  ${SHORT_ID}  HONEYPOD   ${SERVICE_NAME}"
PADDING=\$(( (LINE_WIDTH - \${#TEXT}) / 2 ))
printf "╔"; for ((i=0; i<LINE_WIDTH; i++)); do printf "═"; done; printf "╗\n"
printf "║%*s%s%*s║\n" "\$PADDING" "" "\$TEXT" "\$((LINE_WIDTH - \${#TEXT} - PADDING))" ""
printf "╚"; for ((i=0; i<LINE_WIDTH; i++)); do printf "═"; done; printf "╝\n"
echo ""
EOF
    docker exec "$CONTAINER_NAME" chmod +x ${BANNER_SCRIPT}
    docker exec "$CONTAINER_NAME" bash -c "grep -qxF '/root/banner.sh' /root/.bashrc || echo '/root/banner.sh' >> /root/.bashrc"
    echo -e "\033[1;32m[✅] Banner for ${SERVICE_NAME} (${SHORT_ID})\033[0m"
  }
  inject_banner "$SERVICE"

  echo -e "\033[1;32m🐝 $SERVICE running on port $PORT (Container: honeypod-$SERVICE)\033[0m"
  echo -e "\033[1;33mLogs:\033[0m $LOG_PATH"
done

echo -e "\033[1;36m[✔] All requested Honeypod services processed.\033[0m"
