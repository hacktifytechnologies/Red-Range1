#!/usr/bin/env bash
# =============================================================================
#  DECOY SETUP — M5: sigint-archive  (v2 — verified against real setup.sh)
#  Challenge : NFS no_root_squash → SUID bash → final flag
#  Network   : v-Priv only
#  NEVER TOUCH:
#    Port 22  (SSH — archivist password auth)
#    Port 2049/111 (real NFS)
#    /etc/exports real entry: /opt/sigint/classified-archive *(no_root_squash)
#    /opt/sigint/classified-archive/  (final flag lives here, mode 600)
#    archivist user / password / SSH config
#  Run as   : sudo bash M5-decoy-sigint-archive.sh
# =============================================================================
# WHAT THIS SCRIPT DOES:
#   1. Adds 5 SAFE (root_squash) NFS decoy exports via add_export_if_missing()
#      — all directories under /opt/decoy-nfs/ (completely separate from the
#      real export path /opt/sigint/classified-archive)
#   2. Installs Samba :139/:445 — 4 archive-themed shares
#   3. Installs vsftpd :21 — archive manifest FTP
#   4. Configures rsync daemon :873 — 2 read-only archive modules
#   5. Installs SNMP :161 — archive node community
#   6. Deploys auditd rules watching /opt/decoy-nfs/, /data/, /etc/exports
#   7. Creates decoy classified directory tree and fake content
#
# GUARANTEED SAFE:
#   - add_export_if_missing() NEVER overwrites /etc/exports — only appends
#   - /opt/sigint/ and /opt/sigint/classified-archive/ are NEVER touched
#   - archivist user is NEVER modified
#   - SSH config is NEVER touched
#   - nfs-kernel-server reinstall is skipped (pkg_install no-op since installed)
#   - exportfs -ra refreshes ALL exports including the real vulnerable one
# =============================================================================

set -euo pipefail
LOG="/root/decoy_setup_log_M5.txt"
exec > >(tee -a "$LOG") 2>&1

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${CYAN}[===] $* [===]${NC}\n"; }

[[ $EUID -ne 0 ]] && { echo "Run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

pkg_install() {
    local to_install=()
    for p in "$@"; do dpkg -s "$p" &>/dev/null || to_install+=("$p"); done
    if [[ ${#to_install[@]} -gt 0 ]]; then apt-get install -y -qq "${to_install[@]}"; fi
}

# ── NFS safe-append helper ────────────────────────────────────────────────────
# Appends an export line to /etc/exports ONLY if the directory path is not
# already present. NEVER rewrites or truncates the file.
# The real entry (/opt/sigint/classified-archive) is left completely untouched.
add_export_if_missing() {
    local line="$1"
    local dir
    dir=$(echo "$line" | awk '{print $1}')
    if grep -qF "$dir" /etc/exports 2>/dev/null; then
        warn "NFS export already present, skipping: $dir"
    else
        echo "$line" >> /etc/exports
        info "NFS export added: $dir"
    fi
}

# =============================================================================
# PREFLIGHT — Confirm we are NOT about to break the real NFS export
# =============================================================================
section "Preflight — Verifying Real NFS Export Is Intact"

if ! grep -qF "/opt/sigint/classified-archive" /etc/exports 2>/dev/null; then
    warn "/opt/sigint/classified-archive NOT found in /etc/exports yet."
    warn "Run the real M5 setup.sh first, then re-run this decoy script."
    warn "Continuing — decoy exports will be appended when real entry appears."
fi

info "Real NFS export protected. Adding decoy exports only."

# =============================================================================
# 1. NFS — 5 Decoy Exports (all root_squash — SAFE)
#    All under /opt/decoy-nfs/ — completely separate from /opt/sigint/
# =============================================================================
section "NFS — 5 Decoy Exports (root_squash, Port 2049)"

# nfs-kernel-server is already installed by real setup.sh — pkg_install is a no-op
pkg_install nfs-kernel-server

mkdir -p /opt/decoy-nfs/ops-logs
mkdir -p /opt/decoy-nfs/freq-archive
mkdir -p /opt/decoy-nfs/config-backup
mkdir -p /opt/decoy-nfs/proc-results
mkdir -p /opt/decoy-nfs/audit-logs

# Populate decoy dirs with realistic-looking content
cat > /opt/decoy-nfs/ops-logs/ops-log-2025-04-17.txt << 'TXT'
[DESERT WIRE OPS LOG — 2025-04-17 — UNCLASSIFIED]
0001Z - Shift change. Alpha team on watch.
0345Z - relay-node-03 latency spike detected (340ms). Monitoring.
0600Z - Band rotation executed. ALPHA-LO now active.
1200Z - Band rotation executed. BRAVO-LO now active.
1800Z - Band rotation executed. BRAVO-HI now active.
2359Z - End of day. No significant SIGACT.
TXT

cat > /opt/decoy-nfs/freq-archive/archive-manifest-2025-04.txt << 'TXT'
# DESERT WIRE — Frequency Archive Manifest — April 2025
# Updated: 2025-04-17T23:59:00Z
# Classification: UNCLASSIFIED // EXERCISE
20250401_ALPHA-LO.cap  SHA256:a3f4b2c1d8e9f0...
20250401_ALPHA-HI.cap  SHA256:b4c5d3e2f1a0b9...
20250402_BRAVO-LO.cap  SHA256:c5d6e4f3a2b1c0...
[... 28 more entries ...]
TXT

cat > /opt/decoy-nfs/config-backup/gateway-config-backup-2025-04-17.json << 'JSON'
{
  "_note":        "Gateway config backup — automated daily snapshot",
  "_backup_time": "2025-04-17T23:00:00Z",
  "service":      "sigint-gateway",
  "cached_token": "DSRT-BACKUP-STALE-XXXXXXXXXXXXXXXX",
  "cache_valid":  false
}
JSON

cat > /opt/decoy-nfs/proc-results/job-results-2025-04-17.json << 'JSON'
{"date":"2025-04-17","jobs_completed":244,"jobs_failed":3,
 "total_bytes_processed":193847200,"last_export":"sigint-archive.kestrel.mil"}
JSON

cat > /opt/decoy-nfs/audit-logs/auditd-2025-04-17.log << 'TXT'
type=SYSCALL arch=x86_64 syscall=openat success=yes pid=2341 comm="archive-sync"
type=PATH item=0 name="/opt/decoy-nfs/proc-results/job-results-2025-04-16.json"
type=SYSCALL arch=x86_64 syscall=openat success=yes pid=2341 comm="archive-sync"
type=PATH item=0 name="/opt/decoy-nfs/ops-logs/ops-log-2025-04-16.txt"
TXT

# Append the 5 decoy exports — root_squash makes all of these SAFE
add_export_if_missing "/opt/decoy-nfs/ops-logs      *(ro,sync,no_subtree_check,root_squash)"
add_export_if_missing "/opt/decoy-nfs/freq-archive  *(ro,sync,no_subtree_check,root_squash)"
add_export_if_missing "/opt/decoy-nfs/config-backup *(ro,sync,no_subtree_check,root_squash)"
add_export_if_missing "/opt/decoy-nfs/proc-results  *(ro,sync,no_subtree_check,root_squash)"
add_export_if_missing "/opt/decoy-nfs/audit-logs    *(ro,sync,no_subtree_check,root_squash)"

# Refresh exports — includes the real vulnerable export unchanged
exportfs -ra
info "NFS decoy exports registered — real export untouched"
info "Exports now:"
exportfs -v | grep -v "classified-archive" | head -10 || true

# =============================================================================
# 2. SAMBA — 4 Archive-Themed Shares (Ports 139, 445)
# =============================================================================
section "Samba — Archive SMB Shares (Ports 139/445)"
pkg_install samba

mkdir -p /srv/samba/signal-archive
mkdir -p /srv/samba/ops-reports
mkdir -p /srv/samba/it-docs
mkdir -p /srv/samba/backup-staging

# Populate shares
cat > /srv/samba/signal-archive/README.txt << 'TXT'
KESTREL Signal Archive — Processed Collection
===============================================
This share contains finalized signal collection records.
Access: Read-only for archive team
Contact: archive-ops@kestrel.mil
TXT

cat > /srv/samba/signal-archive/archive-index-2025-Q1.txt << 'TXT'
Q1 2025 Signal Archive Index
==============================
JAN: 7,342 intercepts processed, 247 priority hits
FEB: 8,104 intercepts processed, 312 priority hits
MAR: 7,981 intercepts processed, 289 priority hits
Status: COMPLETE — archived to long-term storage
TXT

cat > /srv/samba/ops-reports/weekly-ops-2025-04-14.txt << 'TXT'
WEEKLY OPS REPORT — 14 APR 2025 — DESERT WIRE
================================================
Collection performance: 97.2% uptime
Relay node status: 4/5 operational
Priority collection: 23 hits this week
Upcoming rotation: 18 APR 2025 06:00Z
TXT

cat > /srv/samba/it-docs/network-diagram.txt << 'TXT'
FOB KESTREL Network Architecture — UNCLASSIFIED
=================================================
[Internet] -- WireGuard VPN --> [v-Pub]
[v-Pub] --> M1:sigint-relay (port 80)
[v-DMZ] --> M2:sigint-monitor (port 8080)
[v-DMZ] --> M3:sigint-gateway (SSH only — pivot)
[v-Priv] --> M4:sigint-processor (port 5000)
[v-Priv] --> M5:sigint-archive (SSH + NFS)
TXT

cat > /srv/samba/backup-staging/backup-manifest-2025-04.txt << 'TXT'
Backup Manifest — April 2025
==============================
staging/2025-04-17/ — IN PROGRESS
staging/2025-04-16/ — COMPLETE
staging/2025-04-15/ — COMPLETE
Storage used: 48.3 GB / 200 GB
TXT

# Set permissions
chmod -R 755 /srv/samba/

cat > /etc/samba/smb.conf << 'SAMBA'
[global]
   workgroup = KESTREL
   server string = FOB KESTREL Archive Server
   netbios name = SIGINT-ARCHIVE
   security = user
   map to guest = bad user
   log file = /var/log/samba/log.%m
   max log size = 50
   server min protocol = NT1

[signal-archive]
   comment = SIGINT Signal Archive (Read-Only)
   path = /srv/samba/signal-archive
   read only = yes
   guest ok = yes
   browseable = yes

[ops-reports]
   comment = Operations Reports
   path = /srv/samba/ops-reports
   read only = yes
   guest ok = yes
   browseable = yes

[it-docs]
   comment = IT Documentation
   path = /srv/samba/it-docs
   read only = yes
   guest ok = yes
   browseable = yes

[backup-staging]
   comment = Backup Staging Area
   path = /srv/samba/backup-staging
   read only = no
   guest ok = no
   valid users = archive-ftp
   browseable = yes
SAMBA

mkdir -p /var/log/samba
systemctl enable smbd nmbd --quiet 2>/dev/null || true
systemctl restart smbd 2>/dev/null || systemctl start smbd
systemctl restart nmbd 2>/dev/null || systemctl start nmbd
info "Samba shares on :139/:445"

# =============================================================================
# 3. VSFTPD — Archive Manifest FTP (Port 21)
# =============================================================================
section "vsftpd — Archive Manifest FTP (Port 21)"
pkg_install vsftpd

useradd -m -s /bin/false archive-ftp 2>/dev/null || true
echo "archive-ftp:ArchFtp2024Kestrel" | chpasswd

mkdir -p /srv/ftp/archive-manifests
mkdir -p /srv/ftp/archive-checksums
mkdir -p /srv/ftp/export-logs
chown -R nobody:nogroup /srv/ftp 2>/dev/null || true

cat > /srv/ftp/archive-manifests/manifest-2025-04.txt << 'TXT'
KESTREL Archive Export Manifest — April 2025
=============================================
Generated: 2025-04-17T23:00:00Z

DAILY ARCHIVES:
  2025-04-01 — ops-log, freq-archive (COMPLETE)
  2025-04-02 — ops-log, freq-archive (COMPLETE)
  [... 14 more daily entries ...]
  2025-04-17 — ops-log, freq-archive (IN PROGRESS)

CONTACT: archive-ops@kestrel.mil
TXT

cat > /srv/ftp/archive-checksums/checksums-2025-04.sha256 << 'TXT'
a3f4b2c1d8e9f0a1b2c3d4e5f6a7b8c9  /opt/decoy-nfs/ops-logs/ops-log-2025-04-16.txt
b4c5d3e2f1a0b9c8d7e6f5a4b3c2d1e0  /opt/decoy-nfs/freq-archive/archive-manifest-2025-03.txt
TXT

cat > /srv/ftp/export-logs/export-log-2025-04-17.txt << 'TXT'
[2025-04-17 23:00:01] START export job EXP-2025-0417
[2025-04-17 23:00:03] Source: /opt/decoy-nfs/ops-logs
[2025-04-17 23:00:04] Destination: sigint-archive.kestrel.mil:/archives/ops
[2025-04-17 23:00:08] 1 file(s) transferred — 847 bytes
[2025-04-17 23:00:08] END — status: OK
TXT

mkdir -p /var/run/vsftpd/empty

cat > /etc/vsftpd.conf << 'VSFTPD'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=YES
write_enable=NO
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_file=/var/log/vsftpd.log
ftpd_banner=KESTREL Signal Archive FTP — Authorized Personnel Only
anon_root=/srv/ftp
local_root=/srv/ftp
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
VSFTPD

systemctl enable vsftpd --quiet
systemctl restart vsftpd 2>/dev/null || systemctl start vsftpd
info "vsftpd archive FTP on :21"

# =============================================================================
# 4. RSYNC DAEMON — Read-only Archive Backup (Port 873)
# =============================================================================
section "Rsync Daemon — Archive Backup Sync (Port 873)"
pkg_install rsync

mkdir -p /opt/decoy-nfs/rsync-staging

cat > /etc/rsyncd.conf << 'RSYNC'
uid = nobody
gid = nogroup
use chroot = yes
max connections = 4
pid file = /var/run/rsyncd.pid
log file = /var/log/rsyncd.log

[archive-ro]
    path = /opt/decoy-nfs/ops-logs
    comment = Archive Operations Logs (Read Only)
    read only = yes
    list = yes
    auth users = backup-agent
    secrets file = /etc/rsyncd.secrets

[ops-logs-ro]
    path = /opt/decoy-nfs/freq-archive
    comment = Frequency Archive Data (Read Only)
    read only = yes
    list = yes
    auth users = backup-agent
    secrets file = /etc/rsyncd.secrets
RSYNC

echo "backup-agent:BkupAgentK3strel2024" > /etc/rsyncd.secrets
chmod 600 /etc/rsyncd.secrets

cat > /etc/systemd/system/rsync-daemon.service << 'SVC'
[Unit]
Description=KESTREL Archive Rsync Daemon
After=network.target

[Service]
ExecStart=/usr/bin/rsync --daemon --no-detach --config=/etc/rsyncd.conf
Restart=always
RestartSec=5
User=nobody

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  rsync-daemon.service --quiet
systemctl restart rsync-daemon.service 2>/dev/null \
    || systemctl start rsync-daemon.service
info "Rsync daemon on :873 — modules: archive-ro, ops-logs-ro"

# =============================================================================
# 5. SNMP — Archive Node Monitoring (Port 161 UDP)
# =============================================================================
section "SNMP — Archive Node Monitoring (Port 161 UDP)"
pkg_install snmpd snmp

cat > /etc/snmp/snmpd.conf << 'SNMP'
agentAddress udp:161,tcp:161
rocommunity public default
rocommunity kestrel_archive 195.0.0.0/8
sysLocation "FOB KESTREL — Classified Signal Archive — Private Network"
sysContact  "Archive Ops <archive-ops@iwdesert.mil>"
sysName     "sigint-archive.iwdesert.mil"
sysDescr    "KESTREL Archive Node — Ubuntu 22.04 LTS — NFS Server"
sysServices 76
SNMP

systemctl enable snmpd --quiet
systemctl restart snmpd 2>/dev/null || systemctl start snmpd
info "SNMP on :161"

# =============================================================================
# 6. AUDITD — Watch Decoy Directories
# =============================================================================
section "Auditd — Decoy Directory Watches"
pkg_install auditd

cat > /etc/audit/rules.d/99-desert-wire-archive.rules << 'AUDIT'
## DESERT WIRE — Archive Monitoring Rules
-w /opt/decoy-nfs/           -p rwa -k decoy_archive_access
-w /data/                    -p rwa -k data_dir_access
-w /etc/exports              -p rw  -k nfs_exports_change
-a always,exit -F arch=b64 -S mount -k nfs_mount_attempt
-a always,exit -F arch=b64 -S umount2 -k nfs_umount_attempt
AUDIT

service auditd restart 2>/dev/null || systemctl restart auditd 2>/dev/null || true
info "Auditd rules watching /opt/decoy-nfs/, /data/, /etc/exports"

# =============================================================================
# 7. DECOY DIRECTORY TREE — Realistic Classified Content
# =============================================================================
section "Decoy Classified Directory Tree"

mkdir -p /data/source-registry
mkdir -p /data/frequency-logs
mkdir -p /data/sigint-store/raw
mkdir -p /data/sigint-store/processed
mkdir -p /data/sigint-store/exported
mkdir -p /data/sigint-store/quarantine

cat > /data/source-registry/REGISTRY_NOTICE.txt << 'TXT'
KESTREL SOURCE REGISTRY — CLASSIFICATION: TOP SECRET // SIGINT // NOFORN
=========================================================================
This registry is maintained by the Collection Management Office.
Unauthorized access is a violation of federal law.

Contact: comsec@kestrel.mil
TXT

cat > /data/frequency-logs/freq-log-2025-04-17.txt << 'TXT'
[FREQUENCY LOG — 2025-04-17 — KESTREL]
00:00Z  30-88 MHz band — active
06:00Z  225-400 MHz band — active
12:00Z  30-88 MHz band — active (BRAVO)
18:00Z  1350-1850 MHz band — active (BRAVO-HI)
23:59Z  Log closed — no anomalies
TXT

cat > /data/sigint-store/processed/intercept-meta-2025-04-17.json << 'JSON'
{"date":"2025-04-17","total":244,"priority":5,"archived":241,
 "archive_dest":"nfs://sigint-archive.kestrel.mil/opt/sigint/classified-archive",
 "status":"COMPLETE"}
JSON

cat > /data/sigint-store/quarantine/README.txt << 'TXT'
QUARANTINE — Signals pending second-level analysis.
Items here are NOT archived until cleared by collection management.
Contact: collection-mgmt@kestrel.mil
TXT

# Key fake content: intercept index pointing to the NFS share
mkdir -p /opt/decoy-nfs/intercept-index

cat > /opt/decoy-nfs/intercept-index/intercept-index-2025-04.json << 'JSON'
{
  "_classification": "UNCLASSIFIED // EXERCISE",
  "period":          "April 2025",
  "total_intercepts": 6841,
  "priority_hits":    147,
  "archive_path":     "/opt/sigint/classified-archive/intercepts/",
  "nfs_export":       "sigint-archive.kestrel.mil:/opt/sigint/classified-archive",
  "_note": "This index is cached. Access live data via the NFS export."
}
JSON

add_export_if_missing \
    "/opt/decoy-nfs/intercept-index *(ro,sync,no_subtree_check,root_squash)"

# Refresh exports again after adding the intercept-index export
exportfs -ra
info "Decoy classified tree in /data/ and /opt/decoy-nfs/"

# =============================================================================
# 8. FAKE LOG FILES
# =============================================================================
section "Fake Pre-populated Archive Logs"

mkdir -p /var/log/archive-agent

cat > /var/log/archive-agent/archive.log << 'LOG'
2025-04-17 23:00:01 [INFO]  archive-agent started — version 1.2.4
2025-04-17 23:00:03 [INFO]  NFS mounts verified
2025-04-17 23:00:04 [INFO]  FTP service: UP
2025-04-17 23:00:05 [INFO]  Rsync modules: archive-ro, ops-logs-ro — READY
2025-04-17 23:00:08 [INFO]  EXP-2025-0417: ops-logs exported — 1 file, 847 bytes
2025-04-17 23:01:02 [INFO]  EXP-2025-0417: freq-archive exported — 3 files, 12840 bytes
2025-04-17 23:01:03 [INFO]  EXP-2025-0417: COMPLETE
2025-04-18 04:00:00 [INFO]  Heartbeat OK — NFS: 6 exports active
LOG

info "Archive log at /var/log/archive-agent/archive.log"

# =============================================================================
# 9. UFW
# =============================================================================
section "UFW — Allow Decoy Ports (real ports preserved)"
if command -v ufw &>/dev/null; then
    ufw allow 22   &>/dev/null || true   # SSH (archivist password auth)
    ufw allow 2049 &>/dev/null || true   # NFS — real vulnerable export
    ufw allow 111  &>/dev/null || true   # rpcbind — required for NFS
    ufw --force enable &>/dev/null || true
    for PORT in 21 139 161/udp 445 873; do
        ufw allow "$PORT" &>/dev/null || true
    done
    info "UFW rules added (22 + 2049 + 111 + decoy ports)"
fi

# =============================================================================
# 10. FINAL STATE VERIFICATION
# =============================================================================
section "Final State Verification"

echo "--- /etc/exports ---"
cat /etc/exports
echo ""
echo "--- Active NFS exports ---"
exportfs -v 2>/dev/null || true
echo ""
echo "--- Real export untouched ---"
if grep -qF "classified-archive" /etc/exports; then
    info "Real NFS export /opt/sigint/classified-archive still present — GOOD"
else
    warn "Real NFS export NOT found in /etc/exports — run real setup.sh first!"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "M5 Decoy Setup Complete"
cat << 'SUMMARY'
================================================================
  M5: sigint-archive — Decoy Services
  Challenge: NFS no_root_squash → SUID bash (UNTOUCHED)
             archivist user/password — UNTOUCHED
             /opt/sigint/classified-archive/ — UNTOUCHED
             /etc/exports real entry — UNTOUCHED
----------------------------------------------------------------
  NFS  :2049  6 decoy exports (all root_squash, safe):
               /opt/decoy-nfs/ops-logs
               /opt/decoy-nfs/freq-archive
               /opt/decoy-nfs/config-backup
               /opt/decoy-nfs/proc-results
               /opt/decoy-nfs/audit-logs
               /opt/decoy-nfs/intercept-index
  Samba :139/445  signal-archive, ops-reports, it-docs, backup-staging
  vsftpd :21      archive manifest FTP
  rsync  :873     archive-ro, ops-logs-ro modules
  SNMP   :161     communities: public, kestrel_archive

  Decoy dirs: /opt/decoy-nfs/   (separate from /opt/sigint/)
              /data/sigint-store/, /data/frequency-logs/, /data/source-registry/

  SSH  :22    — UNTOUCHED
  NFS  :2049  — real export UNTOUCHED, decoy exports added
  Real /etc/exports entry — UNTOUCHED
  /opt/sigint/classified-archive/ — UNTOUCHED
  archivist user — UNTOUCHED
================================================================
SUMMARY
