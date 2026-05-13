#!/bin/bash

# SigNoz Proxmox VM Setup Script
# Version: Clean / Production-Ready
# Optimization: 3GB+ RAM

set -e

echo "Starting SigNoz Environment Setup..."

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
DOCKER_GROUP_CHANGED=0
DOCKER_CMD="docker"

# 1. Prompt for User Configuration
read -p "Enter Internal Domain (e.g., signoz.internal): " SIGNOZ_DOMAIN
read -s -p "Enter Admin Password: " SIGNOZ_PASSWORD
echo ""

# 2. Update and Install Dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common ufw htop openssl

# 3. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
else
    echo "Docker already installed."
fi

if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    echo "Adding $TARGET_USER to docker group..."
    sudo usermod -aG docker "$TARGET_USER"
    DOCKER_GROUP_CHANGED=1
else
    echo "$TARGET_USER is already in docker group."
fi

if ! docker ps >/dev/null 2>&1; then
    DOCKER_CMD="sudo docker"
fi

# 4. Generate Caddy Password Hash
echo "Generating security tokens..."
SIGNOZ_PASSWORD_HASH=$($DOCKER_CMD run --rm caddy:2-alpine caddy hash-password --plaintext "$SIGNOZ_PASSWORD")
SIGNOZ_TOKENIZER_JWT_SECRET=$(openssl rand -hex 32)

# 5. Create .env file
echo "Creating environment configuration..."
cat <<EOF > .env
SIGNOZ_DOMAIN=$SIGNOZ_DOMAIN
SIGNOZ_ADMIN_PASSWORD_HASH='$SIGNOZ_PASSWORD_HASH'
SIGNOZ_TOKENIZER_JWT_SECRET=$SIGNOZ_TOKENIZER_JWT_SECRET
EOF
sudo chown "$TARGET_UID:$TARGET_GID" .env

# 6. Setup Swap (Crucial for 2GB RAM)
echo "Setting up 4GB Swap file..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "Swap file created."
else
    echo "Swap file already exists."
fi

if ! swapon --show=NAME --noheadings | grep -qx "/swapfile"; then
    sudo swapon /swapfile
    echo "Swap file enabled."
else
    echo "Swap file already enabled."
fi

if ! grep -q '^/swapfile none swap sw 0 0$' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# 7. Configure Firewall
echo "Configuring UFW Firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 4317/tcp
sudo ufw allow 4318/tcp
sudo ufw --force enable
echo "Firewall configured. Ports 22, 80, 443, 4317, 4318 open."

# 8. Create Data Directories
echo "Creating data directories..."
mkdir -p data/clickhouse data/zookeeper data/alertmanager data/signoz data/caddy_data data/caddy_config
sudo chown -R "$TARGET_UID:$TARGET_GID" data/clickhouse data/zookeeper data/signoz data/caddy_data data/caddy_config

echo ""
echo "Setup Complete!"
echo "-------------------------------------------------------"
echo "Next Steps:"
if [ "$DOCKER_GROUP_CHANGED" -eq 1 ]; then
    echo "1. Apply docker group access now with: newgrp docker"
    echo "   Or log out and log back in before running docker without sudo."
else
    echo "1. Docker group access is already active for $TARGET_USER."
fi
echo "2. Run: docker compose up -d"
echo "3. Access SigNoz at: https://$SIGNOZ_DOMAIN"
echo "   Caddy basic auth user: admin"
echo "   Caddy basic auth password: the password entered above"
echo "-------------------------------------------------------"
