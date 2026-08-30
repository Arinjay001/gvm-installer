#!/bin/bash
set -e

# Screen Clear
clear

echo "========================================"
echo "      GVM Panel Automated Installer     "
echo "========================================"

# 1. Credentials Input
read -p "Enter GitHub Username (e.g., Arinjay001): " GIT_USER
read -s -p "Enter GitHub PAT: " GIT_TOKEN
echo ""

# 2. Update aur Install Dependencies (Node 20 LTS + PostgreSQL)
echo "-> Installing dependencies & PostgreSQL Database..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs git curl postgresql postgresql-contrib

# 3. Database Auto-Configuration
echo "-> Configuring Local Database..."
sudo -u postgres psql -c "CREATE DATABASE gvmpanel;" || true
sudo -u postgres psql -c "CREATE USER gvmuser WITH PASSWORD 'gvmpassword123';" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE gvmpanel TO gvmuser;" || true
sudo -u postgres psql -c "ALTER DATABASE gvmpanel OWNER TO gvmuser;" || true

DB_URL="postgresql://gvmuser:gvmpassword123@localhost:5432/gvmpanel?schema=public"

# 4. Clone Private Repo
INSTALL_DIR="/opt/gvm-panel"
echo "-> Downloading GVM Panel..."
rm -rf "$INSTALL_DIR"
git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/${GIT_USER}/GVM-panel.git $INSTALL_DIR

# 5. Build Server & Setup DB Schema
echo "-> Building Server..."
cd $INSTALL_DIR/server
npm install
echo "DATABASE_URL=\"$DB_URL\"" > .env
npx prisma generate
npx prisma db push
npm run build

# 6. Build Node-System
echo "-> Building Node-System..."
cd $INSTALL_DIR/node-system
npm install

# 7. Setup Background Services
echo "-> Configuring systemd services..."
cat <<SERVICE1 > /etc/systemd/system/gvm-panel.service
[Unit]
Description=GVM Panel Backend
After=network.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/server
ExecStart=/usr/bin/npm run start
Restart=always
[Install]
WantedBy=multi-user.target
SERVICE1

cat <<SERVICE2 > /etc/systemd/system/gvm-node-system.service
[Unit]
Description=GVM Node System
After=network.target
[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR/node-system
ExecStart=/usr/bin/npm run start
Restart=always
[Install]
WantedBy=multi-user.target
SERVICE2

systemctl daemon-reload
systemctl enable --now gvm-panel gvm-node-system

echo "========================================"
echo " Setup Completed Successfully! "
echo "========================================"
