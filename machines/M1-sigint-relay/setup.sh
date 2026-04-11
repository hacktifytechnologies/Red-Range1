#!/bin/bash
# Operation DESERT WIRE — M1: sigint-relay
# Vulnerability: SSRF via Satellite Uplink Checker
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[*] M1 sigint-relay setup"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates 2>/dev/null
# Require Node.js v16+ — system default on Ubuntu 22.04 is too old
if ! node --version 2>/dev/null | grep -qE "^v(1[6-9]|[2-9][0-9])"; then
    echo "[*] Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs 2>/dev/null
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y authbind nmap 2>/dev/null
touch /etc/authbind/byport/80
chown sigint:sigint /etc/authbind/byport/80 2>/dev/null || true
chmod 755 /etc/authbind/byport/80

# Create service user
id sigint &>/dev/null || useradd -r -s /bin/false -d /opt/sigint sigint

# Deploy app
mkdir -p /opt/sigint/relay
cp -r "$SCRIPT_DIR/app/." /opt/sigint/relay/
chown -R sigint:sigint /opt/sigint/relay
cd /opt/sigint/relay && npm install --quiet 2>/dev/null

# Generate flag
FLAG="{ssrf_relay_breach_achieved}"
mkdir -p /opt/sigint/classified
echo "$FLAG" > /opt/sigint/classified/flag1.txt
chmod 640 /opt/sigint/classified/flag1.txt
chown sigint:sigint /opt/sigint/classified/flag1.txt

# Hint for attacker (accessible after SSRF gives RCE)
cat > /opt/sigint/relay/internal_hint.json << 'EOF'
{
  "system": "sigint-monitor",
  "note": "Network monitoring console accessible on DMZ port 8080",
  "credential_note": "Default credentials stored in monitor bootstrap config"
}
EOF

# Access log for blue team
touch /var/log/desertrelay.log
chown sigint:sigint /var/log/desertrelay.log
chmod 644 /var/log/desertrelay.log

# Systemd service
cat > /etc/systemd/system/sigint-relay.service << 'UNIT'
[Unit]
Description=DESERT WIRE — SIGINT Comms Relay Dashboard
After=network.target
[Service]
User=sigint
WorkingDirectory=/opt/sigint/relay
ExecStart=/usr/bin/authbind --deep /usr/bin/node server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
Environment=PORT=80
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sigint-relay
systemctl start sigint-relay

echo "========================================" >> /root/ctf_setup_log.txt
echo "M1 (sigint-relay) Flag: $FLAG" >> /root/ctf_setup_log.txt
echo "Setup: $(date)" >> /root/ctf_setup_log.txt
echo "[ok] M1 sigint-relay — port 80"
