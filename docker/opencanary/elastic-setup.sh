#!/bin/bash
set -e

# Variables
TARGET_DIR="/opt/docker/opencanary"
ZIP_URL="https://github.com/farooq-001/Opencanary-Notes/raw/master/docker/opencanary/elastic.zip"
ZIP_FILE="$TARGET_DIR/elastic.zip"
EXTRACT_DIR="$TARGET_DIR/elastic"

# Create target directory
sudo mkdir -p "$TARGET_DIR"

# Download the ZIP file
echo "Downloading elastic.zip..."
sudo wget -O "$ZIP_FILE" "$ZIP_URL"

# Install unzip if not present
if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    sudo apt-get update
    sudo apt-get install -y unzip
fi

# Unzip the file
echo "Unzipping elastic.zip..."
sudo unzip -o "$ZIP_FILE" -d "$EXTRACT_DIR"

# Start Docker Compose
echo "Starting Docker Compose..."
cd "$EXTRACT_DIR"
sudo docker compose -f elastic-compose.yml up -d

# Show running containers
echo "Docker containers running:"
sudo docker ps
