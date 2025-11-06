#!/bin/bash
# ============================================================
# Fixed Script to Deploy honeypod-logsender via Docker Compose
# Path: /opt/docker/opencanary/docker-compose/logsender-compose.yml
# ============================================================

set -e  # Exit immediately if any command fails

# Define file path
COMPOSE_PATH="/opt/docker/opencanary/docker-compose"
COMPOSE_FILE="${COMPOSE_PATH}/logsender-compose.yml"

# Create required directories
mkdir -p "$COMPOSE_PATH"
mkdir -p /var/log/honeypod

# Create docker-compose file (no build, no version key)
cat > "$COMPOSE_FILE" <<'EOF'
services:
  honeypod-logsender:
    image: baba001/honeypod-logsender:latest
    container_name: honeypod-logsender
    restart: unless-stopped
    network_mode: host
    volumes:
      - /var/log/honeypod:/var/log/honeypod:ro
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

# Deploy container
echo "[INFO] Starting honeypod-logsender container..."
docker compose -f "$COMPOSE_FILE" up -d

echo "[SUCCESS] honeypod-logsender container deployed successfully."
