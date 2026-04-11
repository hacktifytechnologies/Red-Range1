#!/bin/bash
# Operation DESERT WIRE — M5: sigint-archive
# Vulnerability: NFS no_root_squash → SUID bash escape
set -e
echo "[*] M5 sigint-archive setup"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server nfs-kernel-server 2>/dev/null

# Create archivist user
id archivist &>/dev/null || useradd -m -s /bin/bash archivist
echo "archivist:Arch1v3@D3S3RT" | chpasswd

# Classified archive directory (exported via NFS)
mkdir -p /opt/sigint/classified-archive
mkdir -p /opt/sigint/classified-archive/intercepts
mkdir -p /opt/sigint/classified-archive/selectors

# Decoy files (realistic noise)
cat > /opt/sigint/classified-archive/intercepts/DAILY_SUMMARY_OCT14.txt << 'EOF'
[SIGINT DAILY SUMMARY — OCT 14 2024 — TOP SECRET // SIGINT // NOFORN]
FOB KESTREL COLLECTION REPORT

COLLECTION PERIOD: 0001-2359 14OCT2024
TOTAL INTERCEPTS:  847
PRIORITY HITS:     23
ACTIVE TARGETS:    COBRAxxx1, FOXTROTxxx2, VIPERxxx3 (selectors redacted)

SIGACT:
- 0347Z: PRIORITY ALPHA target — voice intercept — PROCESSING
- 1122Z: PRIORITY BRAVO target — digital traffic — FORWARDED TO NSA
- 1834Z: ELINT — radar emission — azimuth 247deg — LOGGED

NEXT REPORT: 0001Z 15OCT2024
EOF

cat > /opt/sigint/classified-archive/selectors/ACTIVE_SELECTORS.txt << 'EOF'
[ACTIVE COLLECTION SELECTORS — TOP SECRET]
This file is for authorized SIGINT analysts only.
Selector details withheld pending full clearance verification.
Contact: COMSEC@KESTREL.MIL
EOF

# Generate flag in the archive root
FLAG="FLAG{$(openssl rand -hex 8)_nfs_squash_archive_pwned}"
echo "$FLAG" > /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt
chmod 600 /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt
chown root:root /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt

chmod 750 /opt/sigint/classified-archive
chown -R root:root /opt/sigint/classified-archive

# NFS EXPORT — INTENTIONAL MISCONFIGURATION: no_root_squash
# This means a client connecting as root keeps root privileges on this filesystem
cat > /etc/exports << 'EXPORTS'
/opt/sigint/classified-archive *(rw,sync,no_subtree_check,no_root_squash)
EXPORTS

exportfs -ra
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

# SSH config (password auth enabled for archivist)
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd && systemctl enable sshd

echo "========================================" >> /root/ctf_setup_log.txt
echo "M5 (sigint-archive) Flag (FINAL): $FLAG" >> /root/ctf_setup_log.txt
echo "NFS Export: /opt/sigint/classified-archive (no_root_squash)" >> /root/ctf_setup_log.txt
echo "Setup: $(date)" >> /root/ctf_setup_log.txt
echo "[ok] M5 sigint-archive — SSH port 22, NFS port 2049"
