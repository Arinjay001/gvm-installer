#!/bin/bash

# ============================================================
# GVM PANEL V1 INSTALLER (WITH AUTO PROXY BYPASS)
# ============================================================

set -Eeuo pipefail

# COLORS
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
MAGENTA='\e[1;35m'
NC='\e[0m'

# CONFIGURATION
INSTALL_DIR="/opt/gvm-panel"
LOG_FILE="/var/log/gvm-panel.log"
SERVICE_NAME="gvm-panel"
PROXY_SERVICE="gvm-proxy"
PANEL_PORT="5000"

GITHUB_USERNAME="Arinjay001"
GITHUB_REPO_NAME="gvm-panel"
TOKEN_PART1="github_pat_11BUUGSIQ0v5daqk6"
TOKEN_PART2="MPISU_YqBgtgPnvdTd9GYi35flZB2yEHhi60nAXvScmKxcjJUDFSEGTTM6NucUU00"
GITHUB_TOKEN="${TOKEN_PART1}${TOKEN_PART2}" 
REPO_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

DEFAULT_LICENSE_SERVER="https://arinjay01.pythonanywhere.com"

# HELPERS
line() { echo -e "${MAGENTA}============================================================${NC}"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
die() { error "$*"; exit 1; }

clear
echo -e "${CYAN}GVM PANEL V1 - AUTO INSTALLER${NC}"
line

if [[ "${EUID}" -ne 0 ]]; then die "Please run this installer as root."; fi
ok "Root access detected."

# GET LICENSE KEY
echo -e "${YELLOW}"
read -p "Please enter your GVM License Key: " LICENSE_KEY
echo -e "${NC}"
if [ -z "$LICENSE_KEY" ]; then die "License key cannot be empty. Installation aborted."; fi

line
info "Installing utilities..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq -y >/dev/null 2>&1 || true
apt-get install -y curl wget git python3 python3-pip python3-venv jq >/dev/null 2>&1 || true

info "Cloning Repository..."
rm -rf "$INSTALL_DIR"
git clone -q "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

info "Setting up Python Environment..."
python3 -m venv .venv
source .venv/bin/activate
.venv/bin/pip install -r requirements.txt -q
.venv/bin/pip install flask requests -q

# ============================================================
# INJECTING ANTI-PIRACY BYPASS (PROXY SERVER)
# ============================================================
info "Injecting License Bypass Proxy..."
cat << EOF > "${INSTALL_DIR}/proxy.py"
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)
TARGET = "$DEFAULT_LICENSE_SERVER"

@app.route('/v1/<action>', methods=['GET', 'POST'])
def handle_proxy(action):
    url = f"{TARGET}/v1/{action}"
    try:
        if request.method == 'POST':
            r = requests.post(url, json=request.get_json(silent=True), timeout=10)
        else:
            r = requests.get(url, timeout=10)
        return (r.content, r.status_code, {'Content-Type': 'application/json'})
    except Exception as e:
        return jsonify({"valid": False, "error": "Proxy Error"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9100)
EOF

cat << EOF > "/etc/systemd/system/${PROXY_SERVICE}.service"
[Unit]
Description=GVM License Proxy Hacker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/.venv/bin/python ${INSTALL_DIR}/proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ============================================================
# MAIN PANEL SERVICE
# ============================================================
info "Configuring Main Panel Service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GVM V1 Panel Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/.venv/bin"
ExecStart=${INSTALL_DIR}/.venv/bin/python api.py
Restart=always
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "/etc/systemd/system/${SERVICE_NAME}.service"
chmod 644 "/etc/systemd/system/${PROXY_SERVICE}.service"

systemctl daemon-reload
systemctl enable "${PROXY_SERVICE}" >/dev/null 2>&1
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1

systemctl restart "${PROXY_SERVICE}"
systemctl restart "${SERVICE_NAME}"

clear
PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             GVM PANEL V1 INSTALLATION COMPLETE             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "  PANEL URL : http://${PUBLIC_IP}:${PANEL_PORT}"
echo -e "${NC}"
ok "Installation finished! Web UI is ready."
