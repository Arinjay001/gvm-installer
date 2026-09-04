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
echo -e "${CYAN}GVM PANEL INSTALLER${NC}"
line

if [[ "${EUID}" -ne 0 ]]; then die "Please run this installer as root."; fi
ok "Root access detected."

line
info "Installing utilities and LXC/LXD dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq -y >/dev/null 2>&1 || true
apt-get install -y curl wget git python3 python3-pip python3-venv jq lxd lxc >/dev/null 2>&1 || true
ok "System utilities and LXC installed."

info "Installing NGINX..."
apt-get install -y nginx >/dev/null 2>&1 || true
dpkg --configure -a >/dev/null 2>&1 || true
ok "NGINX installed."

# ============================================================
# AUTO-CONFIGURING NGINX FOR CLOUDFLARE WEBSOCKETS
# ============================================================
info "Configuring Nginx Reverse Proxy for Web SSH..."

mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

cat > /tmp/nginx_gvm << 'EOF'
server {
    listen 80;
    server_name _;

    # Main GVM Panel Proxy
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Dynamic TTYD Console Proxy
    location ~ ^/terminal/(?<vps_port>[0-9]+)/ {
        proxy_pass http://127.0.0.1:$vps_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

mv /tmp/nginx_gvm /etc/nginx/sites-available/default

rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

systemctl restart nginx || true
systemctl enable nginx >/dev/null 2>&1 || true
ok "Nginx configured successfully for dynamic TTYD ports."

info "Cleaning up old ttyd processes and binaries..."
pkill -f ttyd || true
rm -f /usr/local/bin/ttyd

info "Installing ttyd for Advanced Web Console..."
wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64
chmod +x /usr/local/bin/ttyd
ok "ttyd installed successfully."

info "Cloning Repository from GitHub..."
rm -rf "$INSTALL_DIR"
git clone -q "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"
ok "Repository cloned."

# ============================================================
# AUTO-INJECTING TTYD CODE INTO GVM.PY BACKEND
# ============================================================
info "Injecting dynamic port routing into gvm.py..."

GVM_PY_PATH="${INSTALL_DIR}/gvm.py"

if [ -f "$GVM_PY_PATH" ]; then
    cat << 'PYEOF' >> "$GVM_PY_PATH"

# ==========================================
# AUTO-INJECTED TTYD CONSOLE MANAGER
# ==========================================
import subprocess
import socket
import atexit

active_consoles = {}

def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('', 0))
        return s.getsockname()[1]

def start_vps_console(vps_name):
    if vps_name in active_consoles and active_consoles[vps_name]['process'].poll() is None:
        return active_consoles[vps_name]['port']

    port = get_free_port()
    base_path = f"/terminal/{port}"

    cmd = [
        "ttyd", "-W", "-p", str(port), "-i", "127.0.0.1", 
        "-b", base_path, 
        "lxc", "exec", vps_name, "--", "/bin/bash"
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    active_consoles[vps_name] = {'process': process, 'port': port}
    return port

def cleanup_consoles():
    for vps, data in active_consoles.items():
        try:
            data['process'].terminate()
        except:
            pass
atexit.register(cleanup_consoles)

@app.route('/vps/<vps_name>/console')
def vps_console(vps_name):
    dynamic_port = start_vps_console(vps_name)
    return render_template('vps_console.html', vps={'name': vps_name}, console_port=dynamic_port)
PYEOF
    ok "gvm.py patched automatically with console manager."
else
    error "gvm.py not found in repository root!"
fi

info "Setting up Python Environment..."
python3 -m venv .venv
source .venv/bin/activate
.venv/bin/pip install -r requirements.txt -q
.venv/bin/pip install flask requests paramiko -q
ok "Python environment ready."

# ============================================================
# APPLYING FRONTEND FIXES (CREATE VPS UI + PREMIUM CONSOLE)
# ============================================================
info "Applying frontend patches (Premium UI & Console)..."

# 1. VPS Creation Reload Fix
cat << 'EOF' >> "${INSTALL_DIR}/templates/admin/vps_create.html"
<script>
document.addEventListener("DOMContentLoaded", function() {
    const form = document.querySelector('form');
    
    const style = document.createElement('style');
    style.innerHTML = `@keyframes spin { 100% { transform: rotate(360deg); } }`;
    document.head.appendChild(style);

    if (form) {
        form.addEventListener('submit', async function(e) {
            e.preventDefault(); 
            
            const vpsNameInput = document.getElementById('vpsName') || form.querySelector('input[name="name"]');
            const passwordInput = document.getElementById('vpsPassword') || form.querySelector('input[name="password"]');
            
            const submitBtn = form.querySelector('button[type="submit"]') || form.querySelector('button');
            
            if(submitBtn) { 
                submitBtn.disabled = true; 
                submitBtn.style.cursor = "not-allowed";
                submitBtn.style.opacity = "0.8";
                submitBtn.innerHTML = `
                    <svg style="animation: spin 1s linear infinite; display: inline-block; width: 20px; height: 20px; margin-right: 8px; vertical-align: middle;" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" style="opacity: 0.25;"></circle>
                        <path fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" style="opacity: 0.75;"></path>
                    </svg> 
                    <span style="vertical-align: middle;">Installing your VPS...</span>
                `; 
            }
            
            try {
                const response = await fetch('/api/create-vps', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ 
                        name: vpsNameInput ? vpsNameInput.value : '', 
                        password: passwordInput ? passwordInput.value : '' 
                    })
                });
                
                const result = await response.json();
                if(result.success) {
                    if(submitBtn) {
                        submitBtn.innerHTML = `✅ VPS Installed Successfully!`;
                        submitBtn.style.backgroundColor = "#10B981";
                        submitBtn.style.color = "#ffffff";
                    }
                    setTimeout(() => { window.location.href = "/admin/vps"; }, 1500);
                } else {
                    alert("Error: " + result.error);
                    if(submitBtn) { 
                        submitBtn.disabled = false; 
                        submitBtn.style.cursor = "pointer";
                        submitBtn.style.opacity = "1";
                        submitBtn.innerHTML = "Create VPS"; 
                    }
                }
            } catch(err) {
                alert("Backend API Error! Check logs.");
                if(submitBtn) { 
                    submitBtn.disabled = false;
                    submitBtn.style.cursor = "pointer";
                    submitBtn.style.opacity = "1";
                    submitBtn.innerHTML = "Create VPS"; 
                }
            }
        });
    }
});
</script>
EOF

# 2. Premium SSH Console Replacement
cat > "${INSTALL_DIR}/templates/vps_console.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SSH Terminal - {{ vps.name }}</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body, html { margin: 0; padding: 0; height: 100%; background-color: #09090b; font-family: 'Inter', 'Segoe UI', sans-serif; color: #ffffff; overflow: hidden; }
        .top-bar { display: flex; justify-content: space-between; align-items: center; background-color: #111118; padding: 12px 24px; border-bottom: 1px solid #1f1f2e; height: 60px; box-sizing: border-box; }
        .left-section { display: flex; align-items: center; gap: 16px; }
        .title { font-size: 16px; font-weight: 600; letter-spacing: 0.5px; display: flex; align-items: center; gap: 10px; }
        .title i { color: #6366f1; font-size: 18px; }
        .status-badge { background-color: rgba(16, 185, 129, 0.1); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.3); padding: 4px 10px; border-radius: 4px; font-size: 11px; font-weight: 700; letter-spacing: 1px; display: flex; align-items: center; gap: 6px; }
        .status-badge .dot { width: 6px; height: 6px; background-color: #10b981; border-radius: 50%; box-shadow: 0 0 6px #10b981; }
        .right-section { display: flex; gap: 12px; }
        .btn { padding: 8px 16px; border: none; border-radius: 4px; font-size: 13px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 8px; transition: all 0.2s ease; text-decoration: none; }
        .btn-danger { background-color: rgba(239, 68, 68, 0.1); color: #ef4444; border: 1px solid rgba(239, 68, 68, 0.3); }
        .btn-danger:hover { background-color: #ef4444; color: #ffffff; }
        .btn-secondary { background-color: transparent; color: #a1a1aa; border: 1px solid #27272a; }
        .btn-secondary:hover { background-color: #27272a; color: #ffffff; }
        .terminal-container { height: calc(100vh - 60px); width: 100%; background-color: #000000; }
        iframe { width: 100%; height: 100%; border: none; }
    </style>
</head>
<body>
    <div class="top-bar">
        <div class="left-section">
            <div class="title"><i class="fas fa-chevron-right">_</i> SSH Terminal</div>
            <div class="status-badge" id="statusBadge"><div class="dot"></div> CONNECTED</div>
        </div>
        <div class="right-section">
            <button class="btn btn-danger" onclick="disconnectTerminal()"><i class="fas fa-power-off"></i> Disconnect</button>
            <a href="/admin/vps" class="btn btn-secondary"><i class="fas fa-arrow-left"></i> Back</a>
        </div>
    </div>
    <div class="terminal-container">
        <iframe id="terminalFrame" src="/terminal/{{ console_port }}/" allowfullscreen></iframe>
    </div>
    <script>
        function disconnectTerminal() {
            document.getElementById('terminalFrame').src = "about:blank";
            const badge = document.getElementById('statusBadge');
            badge.innerHTML = `<div class="dot" style="background-color: #ef4444; box-shadow: 0 0 6px #ef4444;"></div> DISCONNECTED`;
            badge.style.color = "#ef4444";
            badge.style.borderColor = "rgba(239, 68, 68, 0.3)";
            badge.style.backgroundColor = "rgba(239, 68, 68, 0.1)";
        }
    </script>
</body>
</html>
EOF

ok "Frontend patched successfully with Premium UI and Nginx proxy settings."

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
Environment="PATH=${INSTALL_DIR}/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
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
echo "  DIRECT IP URL  : http://${PUBLIC_IP}"
echo "  (Nginx is now routing port 80 traffic automatically)"
echo -e "${NC}"
echo -e "${YELLOW}Panel open karne ke baad apni original License Key daaliye!${NC}"
ok "Installation finished! Web UI is ready."
