#!/bin/bash

# SigNoz Proxmox VM Setup Script
# Version: Clean / Production-Ready
# Optimization: 2GB RAM

set -e

echo "Starting SigNoz Environment Setup..."

# 1. Prompt for User Configuration
read -p "Enter Internal Domain (e.g., signoz.internal): " SIGNOZ_DOMAIN
read -s -p "Enter Admin Password: " SIGNOZ_PASSWORD
echo ""

# 2. Update and Install Dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common ufw htop

# 3. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
else
    echo "Docker already installed."
fi

# 4. Generate Caddy Password Hash
echo "Generating security tokens..."
SIGNOZ_PASSWORD_HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "$SIGNOZ_PASSWORD")

# 5. Create .env file
echo "Creating environment configuration..."
cat <<EOF > .env
SIGNOZ_DOMAIN=$SIGNOZ_DOMAIN
SIGNOZ_ADMIN_PASSWORD_HASH=$SIGNOZ_PASSWORD_HASH
EOF

# 6. Setup Swap (Crucial for 2GB RAM)
echo "Setting up 4GB Swap file..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "Swap file created and enabled."
else
    echo "Swap file already exists."
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
mkdir -p data/clickhouse data/alertmanager data/signoz data/caddy_data data/caddy_config
sudo chown -R 1000:1000 data/clickhouse

echo ""
echo "Setup Complete!"
echo "-------------------------------------------------------"
echo "Next Steps:"
echo "1. Log out and log back in (to apply docker group changes)."
echo "2. Run: docker compose up -d"
echo "3. Access SigNoz at: https://$SIGNOZ_DOMAIN"
echo "   User: admin"
echo "-------------------------------------------------------"
