#!/usr/bin/env bash

# ============================================================
# GVM PANEL - ULTRA AUTO-INSTALLER
# ============================================================
set -e

# Colors
GREEN='\e[1;32m'
CYAN='\e[1;36m'
YELLOW='\e[1;33m'
RED='\e[1;31m'
NC='\e[0m'

clear
echo -e "${CYAN}"
cat <<'EOF'
  ____ __     __ __  __   ____                        _ 
 / ___|\ \   / /|  \/  | |  _ \  __ _  _ __    ___  | |
| |  _  \ \ / / | |\/| | | |_) |/ _` || '_ \  / _ \ | |
| |_| |  \ V /  | |  | | |  __/| (_| || | | ||  __/ | |
 \____|   \_/   |_|  |_| |_|    \__,_||_| |_| \___| |_|
                                                       
          ULTRA AUTO-INSTALLER V1.0
EOF
echo -e "${NC}"

# 1. Root Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Is script ko chalane ke liye Root (sudo) permission chahiye!${NC}"
   exit 1
fi
echo -e "${GREEN}[+] Root access confirmed...${NC}"

# 2. Update & Install Dependencies
echo -e "${CYAN}[+] Installing Nginx, Node.js & dependencies...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y nginx git curl unzip > /dev/null 2>&1

# 3. Clone Repository (ASLI LINK YAHAN HAI)
INSTALL_DIR="/opt/gvm-panel"
REPO_URL="https://github.com/Arinjay001/gvm-panel.git"

if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}[!] Purana folder detect hua, usko hata rahe hain...${NC}"
    rm -rf "$INSTALL_DIR"
fi

echo -e "${CYAN}[+] Downloading GVM Panel files...${NC}"
git clone "$REPO_URL" "$INSTALL_DIR" --quiet
cd "$INSTALL_DIR"

# 4. Configure JWT Secret & Prisma
echo -e "${CYAN}[+] Setting up Environment & Database...${NC}"
mkdir -p server
echo 'JWT_SECRET="gvm_super_secret_key_2026"' > server/.env

# 5. Fix Docker TCP (Port 2375)
echo -e "${CYAN}[+] Configuring Docker TCP for Node Management...${NC}"
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375
EOF
systemctl daemon-reload
systemctl restart docker

# 6. Setup Nginx Bridge (Port 80 to 3000)
echo -e "${CYAN}[+] Setting up Nginx Web Server...${NC}"
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80;
    
    location / {
        root /opt/gvm-panel/client/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
systemctl restart nginx

# 7. Setup Systemd Background Service
echo -e "${CYAN}[+] Setting up 24/7 Background Service...${NC}"
cat > /etc/systemd/system/gvm-panel.service << 'EOF'
[Unit]
Description=GVM Panel Daemon
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gvm-panel/server
ExecStart=/usr/bin/node index.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gvm-panel > /dev/null 2>&1
systemctl restart gvm-panel

# Get Public IP
PUBLIC_IP=$(curl -s ifconfig.me)

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}   GVM PANEL SUCCESSFULLY INSTALLED! 🔥${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Panel URL   : http://$PUBLIC_IP"
echo -e "Docker Node : 127.0.0.1:2375 (No Auth)"
echo -e "Directory   : $INSTALL_DIR"
echo -e "${CYAN}Ab aaram se login kijiye!${NC}"
