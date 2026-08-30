#!/bin/bash
set -e

echo "========================================"
echo "      GVM Panel Automated Installer     "
echo "========================================"

INSTALL_DIR="/opt/gvm-panel"

# 1. Ask for Credentials & Database info
echo "Kyunki code private hai, hume GitHub credentials chahiye:"
read -p "Enter GitHub Username (e.g., Arinjay001): " GIT_USER
read -s -p "Enter GitHub Personal Access Token (PAT): " GIT_TOKEN
echo ""
echo "Database connection setup:"
read -p "Enter Database URL (e.g., postgresql://user:pass@localhost:5432/db): " DB_URL

# 2. Install System Dependencies
echo "-> Installing system dependencies (Node.js, Git, curl)..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs git curl

# 3. Clone the Private Repository
echo "-> Cloning private GVM Panel repository..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/${GIT_USER}/GVM-panel.git $INSTALL_DIR

# 4. Setup the Server & Database
echo "-> Building the backend server and syncing Database..."
cd $INSTALL_DIR/server
npm install

# .env file create kar rahe hain
echo "DATABASE_URL=\"$DB_URL\"" > .env

npx prisma generate
npx prisma db push  # Ye database mein tables banayega
npm run build

# 5. Setup the Node-System Daemon
echo "-> Setting up the Node-System daemon..."
cd $INSTALL_DIR/node-system
npm install

# 6. Create Systemd Services
echo "-> Configuring systemctl services..."

# Service 1: Main Server
cat <<EOF > /etc/systemd/system/gvm-panel.service
[Unit]
Description=GVM Panel Backend Server
After=network.target docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/server
ExecStart=/usr/bin/npm run start
Restart=always
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Service 2: Node-System
cat <<EOF > /etc/systemd/system/gvm-node-system.service
[Unit]
Description=GVM Node System Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/node-system
ExecStart=/usr/bin/npm run start  # Agar start command kuch aur hai toh isse change karein
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 7. Enable and Start Services
echo "-> Starting Services via systemctl..."
systemctl daemon-reload
systemctl enable gvm-panel
systemctl enable gvm-node-system
systemctl restart gvm-panel
systemctl restart gvm-node-system

echo "========================================"
echo " Installation Complete! "
echo " Backend Status: systemctl status gvm-panel"
echo " Node-System Status: systemctl status gvm-node-system"
echo "========================================"
