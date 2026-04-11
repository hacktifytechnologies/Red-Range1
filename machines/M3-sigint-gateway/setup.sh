#!/bin/bash
# Operation DESERT WIRE — M3: sigint-gateway
# Vulnerability: sudo /usr/bin/node NOPASSWD (GTFOBin)
set -e
echo "[*] M3 sigint-gateway setup"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server nodejs nmap 2>/dev/null

# Create gateway operations user
id sigops &>/dev/null || useradd -m -s /bin/bash sigops

# Set up SSH authorized_keys (will be populated with M2's generated key)
mkdir -p /home/sigops/.ssh
chmod 700 /home/sigops/.ssh
touch /home/sigops/.ssh/authorized_keys
chmod 600 /home/sigops/.ssh/authorized_keys
chown -R sigops:sigops /home/sigops/.ssh

# NOTE: After running M2 setup, copy M2's public key here:
# cat /opt/monitor/keys/sigops_rsa.pub >> /home/sigops/.ssh/authorized_keys
echo ""
echo "============================================================"
echo "[ACTION REQUIRED] Copy M2 public key to sigops authorized_keys:"
echo "  On M2: cat /opt/monitor/keys/sigops_rsa.pub"
echo "  Append to: /home/sigops/.ssh/authorized_keys on M3"
echo "============================================================"
echo ""

# Configure sudo misconfiguration — sigops can run node as root, no password
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/desert-wire-gateway << 'EOF'
# DESERT WIRE — sigops node diagnostic access (DEV ticket #GW-2201)
# Temporary: node-based network diagnostic tool deployment
# TODO: restrict to specific script path (not done)
sigops ALL=(ALL) NOPASSWD: /usr/bin/node
EOF
chmod 440 /etc/sudoers.d/desert-wire-gateway

# Flag
FLAG="FLAG{sudo_node_pivot_achieved}"
echo "$FLAG" > /root/flag3.txt
chmod 600 /root/flag3.txt

# API token for M4 — stored in gateway config
mkdir -p /opt/gateway
cat > /opt/gateway/config.json << 'CONF'
{
  "role": "signals-gateway",
  "version": "2.1",
  "downstream_services": {
    "sigint_processor": {
      "description": "Signal Processing Cluster API",
      "port": 5000,
      "auth_token": "DSRT-SIG-4a7f2c91",
      "note": "Token valid for /api/signal/process endpoint. Rotate Q1 2025."
    }
  },
  "network": "private-subnet",
  "classification": "SECRET"
}
CONF
chmod 600 /opt/gateway/config.json
chown root:root /opt/gateway/config.json

# SSH config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd && systemctl enable sshd

echo "========================================" >> /root/ctf_setup_log.txt
echo "M3 (sigint-gateway) Flag: $FLAG" >> /root/ctf_setup_log.txt
echo "M3 API Token for M4: DSRT-SIG-4a7f2c91" >> /root/ctf_setup_log.txt
echo "Setup: $(date)" >> /root/ctf_setup_log.txt
echo "[ok] M3 sigint-gateway — SSH key-only auth"
