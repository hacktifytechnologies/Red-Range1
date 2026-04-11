#!/bin/bash
# Operation DESERT WIRE — M2: sigint-monitor
# Vulnerability: OS Command Injection in authenticated diagnostic endpoint
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[*] M2 sigint-monitor setup"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv nmap iputils-ping 2>/dev/null

id sigmon &>/dev/null || useradd -r -s /bin/false -d /opt/sigmon sigmon

mkdir -p /opt/sigmon/monitor
python3 -m venv /opt/sigmon/monitor/venv
/opt/sigmon/monitor/venv/bin/pip install --quiet flask gunicorn 2>/dev/null

cp -r "$SCRIPT_DIR/app/." /opt/sigmon/monitor/
chown -R sigmon:sigmon /opt/sigmon/monitor

# Generate flag
FLAG="FLAG{301d2eaf3e3cfd5c_cmd_inject_monitor}"
mkdir -p /opt/sigmon/classified
echo "$FLAG" > /opt/sigmon/classified/flag2.txt
chmod 640 /opt/sigmon/classified/flag2.txt
chown sigmon:sigmon /opt/sigmon/classified/flag2.txt

# SSH key for M3 sigops user — placed here as loot
mkdir -p /opt/monitor/keys
ssh-keygen -t rsa -b 2048 -f /opt/monitor/keys/sigops_rsa -N "" -q
chmod 600 /opt/monitor/keys/sigops_rsa
chmod 644 /opt/monitor/keys/sigops_rsa.pub
chown -R sigmon:sigmon /opt/monitor/keys

# Log file
touch /var/log/sigint_monitor.log && chown sigmon:sigmon /var/log/sigint_monitor.log && chmod 644 /var/log/sigint_monitor.log

# Systemd service on port 8080
cat > /etc/systemd/system/sigint-monitor.service << 'UNIT'
[Unit]
Description=DESERT WIRE — SIGINT Network Monitor
After=network.target
[Service]
User=sigmon
WorkingDirectory=/opt/sigmon/monitor
ExecStart=/opt/sigmon/monitor/venv/bin/gunicorn --worker-tmp-dir /tmp -w 2 -b 0.0.0.0:8080 --access-logfile /var/log/sigint_monitor.log app:app
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sigint-monitor
systemctl start sigint-monitor

# Store public key on M3 after M3 is set up — this script exports pub key path
echo "M3_PUBKEY_PATH=/opt/monitor/keys/sigops_rsa.pub"
echo "Run on M3: cat /opt/monitor/keys/sigops_rsa.pub >> /home/sigops/.ssh/authorized_keys"

echo "========================================" >> /root/ctf_setup_log.txt
echo "M2 (sigint-monitor) Flag: $FLAG" >> /root/ctf_setup_log.txt
echo "M2 SSH Key for M3: /opt/monitor/keys/sigops_rsa" >> /root/ctf_setup_log.txt
echo "Setup: $(date)" >> /root/ctf_setup_log.txt
echo "[ok] M2 sigint-monitor — port 8080"
echo ""
echo "[IMPORTANT] After M3 is set up, copy sigops public key:"
echo "  ssh-copy-id -i /opt/monitor/keys/sigops_rsa.pub sigops@<M3-IP>"
echo "  OR: cat /opt/monitor/keys/sigops_rsa.pub | ssh sigops@<M3-IP> 'cat >> ~/.ssh/authorized_keys'"
