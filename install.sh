#!/bin/bash
set -e

echo "========================================"
echo "      GVM Panel Automated Installer     "
echo "========================================"

INSTALL_DIR="/opt/gvm-panel"

# 1. Ask for GitHub Credentials
echo "Kyunki code private hai, hume GitHub credentials chahiye:"
read -p "Enter GitHub Username (e.g., Arinjay001): " GIT_USER
read -s -p "Enter GitHub Personal Access Token (PAT): " GIT_TOKEN
echo ""

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

cd $INSTALL_DIR

# 4. Setup the Server
echo "-> Building the backend server..."
cd server
npm install
npx prisma generate
npm run build
cd ..

# 5. Setup the Node-System Daemon
echo "-> Setting up the Node-System daemon..."
cd node-system
npm install
cd ..

# 6. Create Systemd Service
echo "-> Configuring systemctl service..."
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

# 7. Enable and Start Services
echo "-> Starting GVM Panel via systemctl..."
systemctl daemon-reload
systemctl enable gvm-panel
systemctl restart gvm-panel

echo "========================================"
echo " Installation Complete! "
echo " Check status with: systemctl status gvm-panel"
echo "========================================"
