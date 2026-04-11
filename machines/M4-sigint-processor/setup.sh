#!/bin/bash
# Operation DESERT WIRE — M4: sigint-processor
# Vulnerability: Python Pickle Deserialization RCE
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[*] M4 sigint-processor setup"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv nmap 2>/dev/null

id sigproc &>/dev/null || useradd -r -s /bin/false -d /opt/sigproc sigproc

mkdir -p /opt/sigproc/processor
python3 -m venv /opt/sigproc/processor/venv
/opt/sigproc/processor/venv/bin/pip install --quiet flask gunicorn 2>/dev/null

cp -r "$SCRIPT_DIR/app/." /opt/sigproc/processor/
chown -R sigproc:sigproc /opt/sigproc/processor

# Flag
FLAG="FLAG{$(openssl rand -hex 8)_pickle_rce_processor}"
mkdir -p /opt/sigproc/classified
echo "$FLAG" > /opt/sigproc/classified/flag4.txt
chmod 640 /opt/sigproc/classified/flag4.txt
chown sigproc:sigproc /opt/sigproc/classified/flag4.txt

# Archive credentials — loot for M5
mkdir -p /opt/processor/conf
cat > /opt/processor/conf/archive.conf << 'CONF'
[sigint-archive]
# Archive server connection details
# Last updated: 2024-09-14 by SFC Chen
ssh_host = sigint-archive.kestrel.mil
ssh_user = archivist
ssh_pass = Arch1v3@D3S3RT
note     = Automated backup account — password rotation overdue
CONF
chmod 640 /opt/processor/conf/archive.conf
chown sigproc:sigproc /opt/processor/conf/archive.conf

# Access log
touch /var/log/sigint_processor.log
chown sigproc:sigproc /var/log/sigint_processor.log && chmod 644 /var/log/sigint_processor.log

# Systemd
cat > /etc/systemd/system/sigint-processor.service << 'UNIT'
[Unit]
Description=DESERT WIRE — Signal Processing API
After=network.target
[Service]
User=sigproc
WorkingDirectory=/opt/sigproc/processor
ExecStart=/opt/sigproc/processor/venv/bin/gunicorn --worker-tmp-dir /tmp -w 2 -b 0.0.0.0:5000 --access-logfile /var/log/sigint_processor.log app:app
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable sigint-processor
systemctl start sigint-processor

echo "========================================" >> /root/ctf_setup_log.txt
echo "M4 (sigint-processor) Flag: $FLAG" >> /root/ctf_setup_log.txt
echo "M4 API Token (from M3): DSRT-SIG-4a7f2c91" >> /root/ctf_setup_log.txt
echo "Setup: $(date)" >> /root/ctf_setup_log.txt
echo "[ok] M4 sigint-processor — port 5000"
