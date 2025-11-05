#!/bin/bash
# 🐝 Honeypod Stopper Script — Advanced Edition
# Stops honeypod containers, removes their compose files, logs, and config

COMPOSE_BASE="/opt/docker/opencanary/docker-compose"
LOG_BASE="/var/log/honeypod"
CONFIG_BASE="/opt/docker/opencanary/config"

show_banner() {
  clear
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           🐝  HONEYPOD SERVICE STOPPER & CLEANER          ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
}

show_help() {
  show_banner
  echo "Usage:"
  echo "  $0 -s <service>   # Stop and clean a specific honeypod service"
  echo "  $0 --all          # Stop and clean all honeypod services"
  echo ""
  echo "Examples:"
  echo "  $0 -s ssh"
  echo "  $0 --all"
  echo ""
}

stop_and_clean_service() {
  local SERVICE="$1"
  local COMPOSE_FILE="$COMPOSE_BASE/${SERVICE}-compose.yml"
  local LOG_DIR="$LOG_BASE/$SERVICE"
  local CONFIG_FILE="$CONFIG_BASE/${SERVICE}.conf"

  echo "─────────────────────────────────────────────"
  echo "🛑 Stopping honeypod service: $SERVICE"

  # Stop container
  if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null
    echo "✅ Docker containers for $SERVICE stopped."
  else
    echo "⚠️  No compose file found for $SERVICE."
  fi

  # Remove logs
  if [[ -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"
    echo "🧹 Logs cleaned: $LOG_DIR"
  else
    echo "⚠️  No logs found for $SERVICE."
  fi

  # Remove compose file
  if [[ -f "$COMPOSE_FILE" ]]; then
    rm -f "$COMPOSE_FILE"
    echo "🗑️  Compose file removed: $COMPOSE_FILE"
  fi

  # Remove config file
  if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
    echo "🗑️  Config file removed: $CONFIG_FILE"
  else
    echo "⚠️  No config found for $SERVICE."
  fi
}

stop_and_clean_all() {
  echo "🛑 Stopping and cleaning ALL honeypod services..."
  for FILE in "$COMPOSE_BASE"/*-compose.yml; do
    [[ -f "$FILE" ]] || continue
    SERVICE=$(basename "$FILE" -compose.yml)
    stop_and_clean_service "$SERVICE"
  done
  echo ""
  echo "✅ All honeypod services stopped and cleaned."
}

# --- Main logic ---
show_banner

if [[ "${1:-}" == "--all" ]]; then
  stop_and_clean_all
  exit 0
fi

while getopts ":s:h" opt; do
  case $opt in
    s) SERVICE="$OPTARG" ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done

if [[ -z "${SERVICE:-}" ]]; then
  show_help
  exit 1
fi

stop_and_clean_service "$SERVICE"
