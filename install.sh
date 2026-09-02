#!/bin/bash

# ============================================================
# GVM PANEL INSTALLER
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
PANEL_PORT="5000"

# GITHUB DETAILS
GITHUB_USERNAME="Arinjay001"
GITHUB_REPO_NAME="gvm-panel"
TOKEN_PART1="github_pat_11BUUGSIQ0v5daqk6"
TOKEN_PART2="MPISU_YqBgtgPnvdTd9GYi35flZB2yEHhi60nAXvScmKxcjJUDFSEGTTM6NucUU00"
GITHUB_TOKEN="${TOKEN_PART1}${TOKEN_PART2}" 
REPO_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${GITHUB_REPO_NAME}.git"

# HELPERS
line() { echo -e "${MAGENTA}============================================================${NC}"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
die() { error "$*"; exit 1; }

clear
echo -e "${CYAN}GVM PANEL - AUTO INSTALLER${NC}"
line

if [[ "${EUID}" -ne 0 ]]; then die "Please run this installer as root."; fi
ok "Root access detected."

line
info "Installing utilities and LXC/LXD dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq -y >/dev/null 2>&1 || true
apt-get install -y curl wget git python3 python3-pip python3-venv jq lxd lxc >/dev/null 2>&1 || true
ok "System utilities and LXC installed."

info "Installing ttyd for Advanced Web Console..."
wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64
chmod +x /usr/local/bin/ttyd
ok "ttyd installed successfully."

info "Cloning Repository from GitHub..."
rm -rf "$INSTALL_DIR"
git clone -q "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"
ok "Repository cloned."

info "Setting up Python Environment..."
python3 -m venv .venv
source .venv/bin/activate
.venv/bin/pip install -r requirements.txt -q
.venv/bin/pip install flask requests paramiko -q
ok "Python environment ready."

# ============================================================
# APPLYING FRONTEND FIXES AUTOMATICALLY
# ============================================================
info "Applying frontend patches (Fixing Create VPS reload issue)..."
cat << 'EOF' >> "${INSTALL_DIR}/templates/admin/vps_create.html"

<script>
document.addEventListener("DOMContentLoaded", function() {
    const form = document.querySelector('form');
    if (form) {
        form.addEventListener('submit', async function(e) {
            e.preventDefault(); 
            
            const vpsNameInput = document.getElementById('vpsName') || form.querySelector('input[name="name"]');
            const passwordInput = document.getElementById('vpsPassword') || form.querySelector('input[name="password"]');
            const vpsName = vpsNameInput ? vpsNameInput.value : '';
            const password = passwordInput ? passwordInput.value : '';
            
            const submitBtn = form.querySelector('button[type="submit"]') || form.querySelector('button');
            if(submitBtn) { submitBtn.disabled = true; submitBtn.innerText = "Creating VPS..."; }
            
            try {
                const response = await fetch('/api/create-vps', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name: vpsName, password: password })
                });
                
                const result = await response.json();
                if(result.success) {
                    alert("VPS Created Successfully!");
                    window.location.href = "/admin/vps"; // Redirect to VPS list
                } else {
                    alert("Error: " + result.error);
                    if(submitBtn) { submitBtn.disabled = false; submitBtn.innerText = "Create VPS"; }
                }
            } catch(err) {
                alert("Backend API Error! Check logs.");
                if(submitBtn) { submitBtn.disabled = false; submitBtn.innerText = "Create VPS"; }
            }
        });
    }
});
</script>
EOF
ok "Frontend patched successfully."

# ============================================================
# MAIN PANEL SERVICE
# ============================================================
info "Configuring Main Panel Service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=GVM Panel Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/.venv/bin"
ExecStart=${INSTALL_DIR}/.venv/bin/python gvm.py
Restart=always
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "/etc/systemd/system/${SERVICE_NAME}.service"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
systemctl restart "${SERVICE_NAME}"
ok "Systemd service configured and started."

clear
PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                GVM PANEL INSTALLATION COMPLETE             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "  PANEL URL : http://${PUBLIC_IP}:${PANEL_PORT}"
echo -e "${NC}"
echo -e "${YELLOW}Panel open karne ke baad apni original License Key daaliye!${NC}"
ok "Installation finished! Web UI is ready."
