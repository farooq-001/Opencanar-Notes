#!/bin/bash
# 🐝 Honeypod Stopper Script
# Gracefully stops one or all OpenCanary honeypod containers

COMPOSE_BASE="/opt/docker/opencanary/docker-compose"

show_banner() {
  echo ""
  echo "╔═══════════════════════════════════════════════╗"
  echo "║        🐝  HONEYPOD SERVICE STOPPER           ║"
  echo "╚═══════════════════════════════════════════════╝"
  echo ""
}

show_help() {
  show_banner
  echo "Usage:"
  echo "  $0 -s <service>   # Stop a specific honeypod service"
  echo "  $0 --all          # Stop all running honeypod services"
  echo ""
  echo "Examples:"
  echo "  $0 -s ssh"
  echo "  $0 --all"
  echo ""
}

stop_service() {
  local SERVICE="$1"
  local COMPOSE_FILE="$COMPOSE_BASE/${SERVICE}-compose.yml"

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ Compose file not found for service: $SERVICE"
    return
  fi

  echo "🛑 Stopping honeypod service: $SERVICE ..."
  docker compose -f "$COMPOSE_FILE" down --remove-orphans
  echo "✅ Service $SERVICE stopped."
}

stop_all() {
  echo "🛑 Stopping all honeypod services..."
  for file in "$COMPOSE_BASE"/*-compose.yml; do
    [[ -f "$file" ]] || continue
    service=$(basename "$file" -compose.yml)
    stop_service "$service"
  done
  echo "✅ All honeypod containers stopped."
}

# --- Main logic ---
show_banner

if [[ "$1" == "--all" ]]; then
  stop_all
  exit 0
fi

while getopts ":s:h" opt; do
  case $opt in
    s) SERVICE="$OPTARG" ;;
    h) show_help; exit 0 ;;
    *) show_help; exit 1 ;;
  esac
done

if [[ -z "$SERVICE" ]]; then
  show_help
  exit 1
fi

stop_service "$SERVICE"
