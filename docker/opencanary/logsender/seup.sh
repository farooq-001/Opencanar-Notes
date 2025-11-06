#!/bin/bash
# ============================================================
# Simple Script to Create and Start honeypod-logsender Docker Compose
# Path: /opt/docker/opencanary/docker-compose/logsender-compose.yml
# ============================================================

# Define file path
COMPOSE_PATH="/opt/docker/opencanary/docker-compose"
COMPOSE_FILE="${COMPOSE_PATH}/logsender-compose.yml"

# Create required directories
mkdir -p "$COMPOSE_PATH"
mkdir -p /var/log/honeypod

# Create docker-compose file
cat > "$COMPOSE_FILE" <<'EOF'
version: "3.9"

services:
  honeypod-logsender:
    build: .
    container_name: honeypod-logsender
    image: baba001/honeypod-logsender:latest
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

# Go to directory
cd "$COMPOSE_PATH"

# Run docker compose
docker compose -f "$COMPOSE_FILE" up -d --build

echo "[SUCCESS] honeypod-logsender container deployed successfully."
