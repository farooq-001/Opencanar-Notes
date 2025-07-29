#!/bin/bash
 
# OpenCanary Installation Script for Ubuntu/Debian
 
set -e
 
echo "🔧 Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    python3-dev python3-pip \
    python3-virtualenv python3-venv \
    python3-scapy libssl-dev libpcap-dev \
    samba  # for Windows File Share module (optional)
 
echo "📁 Setting up virtual environment..."
virtualenv env/
source env/bin/activate
 
echo "🐍 Installing OpenCanary..."
pip install opencanary
pip install scapy pcapy-ng  # for SNMP module (optional)
 
echo "📝 Creating default configuration file..."
opencanaryd --copyconfig
 
echo "✅ OpenCanary installation complete!"
echo ""
echo "To start in development mode:"
echo "    opencanaryd --dev"
echo ""
echo "Or to run as a service after editing the config:"
echo "    opencanaryd --start"
echo ""
 
echo "📌 To check for port conflicts (e.g., FTP on port 21):"
echo "    sudo netstat -tulnp | grep :21"
 
echo "logs filepath"
 echo   "/var/tmp/opencanary.log"
