#!/bin/bash
set -e
clear

echo "========================================"
echo "    GVM Panel Zero-Click Auto-Installer "
echo "========================================"

# Command line se direct aayega (Koi prompt nahi)
GIT_USER=$1
GIT_TOKEN=$2

if [ -z "$GIT_USER" ] || [ -z "$GIT_TOKEN" ]; then
  echo "Error: Command mein Username ya Token missing hai!"
  exit 1
fi

echo "-> Installing dependencies & PostgreSQL Database..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs git curl postgresql postgresql-contrib

echo "-> Configuring Local Database..."
sudo -u postgres psql -c "CREATE DATABASE gvmpanel;" || true
sudo -u postgres psql -c "CREATE USER gvmuser WITH PASSWORD 'gvmpassword123';" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE gvmpanel TO gvmuser;" || true
sudo -u postgres psql -c "ALTER DATABASE gvmpanel OWNER TO gvmuser;" || true

DB_URL="postgresql://gvmuser:gvmpassword123@localhost:5432/gvmpanel?schema=public"

INSTALL_DIR="/opt/gvm-panel"
echo "-> Downloading GVM Panel..."
rm -rf "$INSTALL_DIR"
git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/${GIT_USER}/GVM-panel.git $INSTALL_DIR

echo "-> Building Server..."
cd $INSTALL_DIR/server
npm install
echo "DATABASE_URL=\"$DB_URL\"" > .env
npx prisma generate
npx prisma db push
npm run build

echo "-> Building Node-System..."
cd $INSTALL_DIR/node-system
npm install

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
