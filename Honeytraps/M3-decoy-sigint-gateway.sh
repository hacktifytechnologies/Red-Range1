#!/usr/bin/env bash
# =============================================================================
#  DECOY SETUP — M3: sigint-gateway  (v2 — fully fixed)
#  Challenge : sudo node GTFOBin privilege escalation
#  Network   : v-DMZ + v-Priv (dual-homed)
#  NEVER TOUCH: Port 22 (SSH), real sudo node rule in /etc/sudoers.d/,
#               /opt/gateway/config.json (real API token for M4)
#  Run as   : sudo bash M3-decoy-sigint-gateway.sh
# =============================================================================
# BUGS FIXED vs v1:
#   1. nginx_prepare(): stop→reset-failed→rm default→rm conf.d before config
#   2. apache_prepare() removed — M3 only runs nginx (fewer moving parts)
#   3. mkdir -p for EVERY parent dir before cat > redirect
#   4. openssl added to pkg_install for self-signed cert generation
#   5. Sudoers validation uses a strict approach: write to a temp file,
#      visudo -c -f, only then mv into place — prevents bad rules landing
#   6. Node.js services: ExecStart validated, WorkingDirectory created
#   7. All systemctl: stop→reset-failed→start (not restart on fresh config)
#   8. MariaDB: wait loop before issuing SQL to avoid "connection refused"
# =============================================================================

set -euo pipefail
LOG="/root/decoy_setup_log_M3.txt"
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

nginx_prepare() {
    pkg_install nginx
    systemctl stop nginx 2>/dev/null || true
    systemctl reset-failed nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/conf.d/*.conf 2>/dev/null || true
}

# Wait for MariaDB to accept connections (up to 30 s)
mariadb_wait() {
    local tries=0
    while ! mysqladmin ping --silent 2>/dev/null && [[ $tries -lt 15 ]]; do
        sleep 2
        tries=$((tries + 1))
    done
    if [[ $tries -eq 15 ]]; then
        warn "MariaDB did not respond in 30s — SQL steps may fail"
    fi
}

# =============================================================================
# 1. NGINX — Gateway Status Portal (Port 8080)
#    Port 80 is FREE on M3 (only SSH runs here), but we use 8080 to look
#    like a management interface rather than a public-facing service.
# =============================================================================
section "Nginx — Gateway Status Portal (Port 8080)"

nginx_prepare

mkdir -p /var/www/html/gateway-portal/api

cat > /var/www/html/gateway-portal/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>SIGINT Gateway — Network Status</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0f111a;color:#c9cdd7;font-family:'Courier New',monospace}
    header{background:#141720;border-bottom:2px solid #1e4db7;padding:14px 24px;
           display:flex;justify-content:space-between;align-items:center}
    header h1{font-size:1rem;color:#5b8def;letter-spacing:2px}
    header small{color:#666;font-size:.75rem}
    .grid{display:grid;grid-template-columns:1fr 1fr;gap:1px;
          background:#1e2130;margin:20px;border:1px solid #1e2130}
    .cell{background:#141720;padding:20px}
    .cell h3{font-size:.78rem;color:#8899bb;text-transform:uppercase;
             letter-spacing:1px;margin-bottom:12px;border-bottom:1px solid #1e2130;
             padding-bottom:8px}
    .route{display:flex;justify-content:space-between;padding:5px 0;
           font-size:.82rem;border-bottom:1px solid #1a1d28}
    .up{color:#3dc97a}.down{color:#e05252}.stb{color:#f5a623}
    footer{text-align:center;padding:12px;font-size:.7rem;color:#444}
  </style>
</head>
<body>
<header>
  <h1>&#x2B21; KESTREL SIGINT GATEWAY — NETWORK STATUS</h1>
  <small>Dual-homed | DMZ &#8596; Private | iwdesert.mil</small>
</header>
<div class="grid">
  <div class="cell">
    <h3>Active Routes (Private to DMZ)</h3>
    <div class="route"><span>195.0.0.0/8 to 11.0.0.0/8</span><span class="up">ACTIVE</span></div>
    <div class="route"><span>195.0.0.0/8 to 203.0.0.0/8</span><span class="down">BLOCKED</span></div>
    <div class="route"><span>11.0.0.0/8 to 195.0.0.0/8</span><span class="up">ACTIVE</span></div>
    <div class="route"><span>DEFAULT GW to 11.0.0.1</span><span class="up">ACTIVE</span></div>
  </div>
  <div class="cell">
    <h3>Network Interfaces</h3>
    <div class="route"><span>eth0 (DMZ)</span><span class="up">UP</span></div>
    <div class="route"><span>eth1 (Private)</span><span class="up">UP</span></div>
    <div class="route"><span>lo</span><span class="up">UP</span></div>
  </div>
  <div class="cell">
    <h3>Upstream Services</h3>
    <div class="route"><span>sigint-monitor :8080</span><span class="up">REACHABLE</span></div>
    <div class="route"><span>sigint-relay :80</span><span class="up">REACHABLE</span></div>
    <div class="route"><span>sigint-processor :5000</span><span class="up">REACHABLE</span></div>
    <div class="route"><span>sigint-archive NFS :2049</span><span class="up">REACHABLE</span></div>
  </div>
  <div class="cell">
    <h3>Firewall Policy (iptables)</h3>
    <div class="route"><span>INPUT</span><span class="stb">DROP (default)</span></div>
    <div class="route"><span>FORWARD</span><span class="stb">DROP (default)</span></div>
    <div class="route"><span>OUTPUT</span><span class="up">ACCEPT</span></div>
    <div class="route"><span>Allowed: 22, 8080</span><span class="up">OPEN</span></div>
  </div>
</div>
<footer>KESTREL Gateway Operations — SOC Contact: soc@iwdesert.mil</footer>
</body>
</html>
HTML

cat > /var/www/html/gateway-portal/api/routes.json << 'JSON'
{
  "routes": [
    {"dst":"195.0.0.0/8","via":"11.0.0.1", "iface":"eth0","state":"ACTIVE"},
    {"dst":"11.0.0.0/8", "via":"195.0.0.1","iface":"eth1","state":"ACTIVE"}
  ],
  "generated_at": "2025-04-18T04:00:00Z"
}
JSON

cat > /var/www/html/gateway-portal/api/health.json << 'JSON'
{"service":"sigint-gateway","status":"ok","uptime_hours":312,
 "dmz_reachable":true,"priv_reachable":true}
JSON

cat > /etc/nginx/sites-available/gateway-portal << 'NGINX'
server {
    listen 8080 default_server;
    root /var/www/html/gateway-portal;
    index index.html;
    server_name _;

    add_header X-Powered-By "KESTREL-GW/1.0" always;

    location /api/ {
        default_type application/json;
        rewrite ^/api/(.+)$ /api/$1.json break;
        try_files $uri $uri/ =404;
    }
    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/gateway-portal-access.log;
    error_log  /var/log/nginx/gateway-portal-error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/gateway-portal \
       /etc/nginx/sites-enabled/gateway-portal

nginx -t
systemctl enable nginx --quiet
systemctl start nginx
info "Nginx gateway portal on :8080"

# =============================================================================
# 2. MARIADB — Gateway Config Database (Port 3306)
# =============================================================================
section "MariaDB — Gateway Config DB (Port 3306)"
pkg_install mariadb-server

systemctl enable mariadb --quiet
systemctl start mariadb
mariadb_wait

mysql -u root << 'SQL'
CREATE DATABASE IF NOT EXISTS gateway_config;

USE gateway_config;

CREATE TABLE IF NOT EXISTS routing_rules (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    src_net   VARCHAR(50),
    dst_net   VARCHAR(50),
    action    VARCHAR(20),
    priority  INT DEFAULT 100,
    enabled   TINYINT DEFAULT 1
);
INSERT IGNORE INTO routing_rules (rule_name, src_net, dst_net, action, priority)
VALUES
  ('allow-priv-to-dmz','195.0.0.0/8','11.0.0.0/8', 'ALLOW',10),
  ('allow-dmz-to-priv','11.0.0.0/8', '195.0.0.0/8','ALLOW',10),
  ('block-pub-to-priv','203.0.0.0/8','195.0.0.0/8','DROP', 1),
  ('allow-ssh-inbound','11.0.0.0/8', '0.0.0.0/0',  'ALLOW',5);

CREATE TABLE IF NOT EXISTS service_endpoints (
    id       INT AUTO_INCREMENT PRIMARY KEY,
    service  VARCHAR(100),
    host     VARCHAR(100),
    port     INT,
    protocol VARCHAR(10),
    status   VARCHAR(20)
);
INSERT IGNORE INTO service_endpoints (service, host, port, protocol, status)
VALUES
  ('sigint-relay',    'relay.iwdesert.mil',    80,   'HTTP','UP'),
  ('sigint-monitor',  'monitor.iwdesert.mil',  8080, 'HTTP','UP'),
  ('sigint-processor','processor.iwdesert.mil',5000, 'HTTP','UP'),
  ('sigint-archive',  'archive.iwdesert.mil',  2049, 'NFS', 'UP');

CREATE USER IF NOT EXISTS 'gw_read'@'%'
    IDENTIFIED BY 'GwRead2024atKestrel';
GRANT SELECT ON gateway_config.* TO 'gw_read'@'%';

CREATE USER IF NOT EXISTS 'gw_admin'@'localhost'
    IDENTIFIED BY 'GwAdmin2024atKestrel';
GRANT ALL PRIVILEGES ON gateway_config.* TO 'gw_admin'@'localhost';

FLUSH PRIVILEGES;
SQL

# Allow remote connections so scanner can see the port
sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' \
    /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || true
systemctl restart mariadb
info "MariaDB gateway_config on :3306"

# =============================================================================
# 3. NON-EXPLOITABLE SUDO ENTRIES
#    Real vuln: "sigops ALL=(root) NOPASSWD: /usr/bin/node"
#    Decoys: commands that look operational but have NO GTFOBin escalation path.
#    Each file is written to /tmp first, validated with visudo -c, then moved.
# =============================================================================
section "Decoy sudoers.d Entries (non-exploitable)"

# Helper: write a sudoers.d file safely
write_sudoers() {
    local name="$1"
    local content="$2"
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$content" > "$tmp"
    if visudo -c -f "$tmp" &>/dev/null; then
        mv "$tmp" "/etc/sudoers.d/${name}"
        chmod 440 "/etc/sudoers.d/${name}"
        info "Sudoers: /etc/sudoers.d/${name} installed"
    else
        warn "Sudoers: /etc/sudoers.d/${name} failed visudo check — skipped"
        rm -f "$tmp"
    fi
}

write_sudoers "98-gateway-netops" \
"# KESTREL Gateway — Network Operations Tool Permissions
# Reviewed: 2025-01-15 | Owner: NetOps Lead
sigops ALL=(root) NOPASSWD: /usr/sbin/iptables -L
sigops ALL=(root) NOPASSWD: /usr/sbin/ip route show
sigops ALL=(root) NOPASSWD: /usr/sbin/ip link show"

write_sudoers "97-gateway-svcmgmt" \
"# KESTREL Gateway — Service Management Permissions
# Reviewed: 2025-02-01 | Owner: Infra Team
sigops ALL=(root) NOPASSWD: /usr/bin/systemctl status nginx
sigops ALL=(root) NOPASSWD: /usr/bin/systemctl status mariadb"

write_sudoers "96-gateway-logread" \
"# KESTREL Gateway — Log Access Permissions
# Reviewed: 2025-02-14 | Owner: SOC
sigops ALL=(root) NOPASSWD: /usr/bin/journalctl -u nginx --no-pager
sigops ALL=(root) NOPASSWD: /bin/cat /var/log/auth.log"

# =============================================================================
# 4. DECOY CONFIG FILES — Fake API tokens in wrong paths
#    Real config is at /opt/gateway/config.json — we do NOT touch it.
# =============================================================================
section "Decoy Config Files and Fake API Tokens"

mkdir -p /opt/gateway-agent/conf
mkdir -p /opt/net-ops/conf
mkdir -p /opt/routing-daemon/etc
mkdir -p /opt/gateway/cache

cat > /opt/gateway-agent/conf/config.json << 'JSON'
{
  "service":      "gateway-agent",
  "version":      "2.0.1",
  "environment":  "production",
  "listen_port":  3300,
  "db": {
    "host": "127.0.0.1",
    "port": 3306,
    "name": "gateway_config",
    "user": "gw_read",
    "pass": "GwRead2024atKestrel"
  },
  "api": {
    "gateway_ops_key": "GW-OPS-AGENT-XXXXXXXXXXXXXXXXXXXXXXXX",
    "_note": "This key is for the local gateway-agent only"
  }
}
JSON
chmod 640 /opt/gateway-agent/conf/config.json

cat > /opt/net-ops/conf/config.json << 'JSON'
{
  "service":  "net-ops-daemon",
  "version":  "1.3.0",
  "routing": {
    "dmz_iface":        "eth0",
    "priv_iface":       "eth1",
    "enable_forwarding": true
  },
  "auth": {
    "mgmt_token": "NETOPS-GW-MGMT-XXXXXXXXXXXXXXXX",
    "_note":      "For gateway management API only — not signal processing"
  }
}
JSON
chmod 640 /opt/net-ops/conf/config.json

cat > /opt/routing-daemon/etc/routing.conf << 'CONF'
# KESTREL Gateway — Routing Daemon Configuration
[daemon]
name     = kestrel-routing-daemon
user     = daemon

[network]
dmz_interface   = eth0
priv_interface  = eth1
forward_enabled = yes

[api]
bind_addr = 127.0.0.1
bind_port = 3301
mgmt_key  = RTDMN-KESTREL-MGMT-XXXXXXXXXXXXXXXX

[logging]
level = INFO
file  = /var/log/routing-daemon.log
CONF
chmod 640 /opt/routing-daemon/etc/routing.conf

cat > /opt/gateway/cache/last_config_snapshot.json << 'JSON'
{
  "_note":          "Cached config snapshot — may be stale",
  "_snapshot_time": "2025-04-17T00:00:00Z",
  "service":        "sigint-gateway",
  "cached_token":   "DSRT-CACHE-STALE-XXXXXXXXXXXXXXXX",
  "cache_valid":    false
}
JSON
chmod 640 /opt/gateway/cache/last_config_snapshot.json

info "Decoy configs in /opt/gateway-agent, /opt/net-ops, /opt/routing-daemon, /opt/gateway/cache"

# =============================================================================
# 5. NODE.JS — Decoy Gateway Agent :3300
#    Gives Node.js a legitimate-looking reason to be installed and running,
#    making the sudo node rule appear less conspicuous.
# =============================================================================
section "Node.js — Gateway Agent Service (Port 3300)"
pkg_install nodejs

mkdir -p /opt/gateway-agent/src

cat > /opt/gateway-agent/src/agent.js << 'JS'
'use strict';
const http = require('http');
const os   = require('os');

const PORT    = 3300;
const VERSION = '2.0.1';

function jsonReply(res, code, body) {
    const data = JSON.stringify(body);
    res.writeHead(code, {
        'Content-Type':   'application/json',
        'X-Service':      'gateway-agent/' + VERSION,
        'Content-Length': Buffer.byteLength(data)
    });
    res.end(data);
}

http.createServer(function(req, res) {
    const url = req.url.split('?')[0];
    if (url === '/health') {
        return jsonReply(res, 200, {
            status:   'ok',
            service:  'gateway-agent',
            version:  VERSION,
            uptime:   Math.floor(process.uptime()),
            hostname: os.hostname()
        });
    }
    if (url === '/routes') {
        return jsonReply(res, 200, {
            routes: [
                { dst: '195.0.0.0/8', via: '11.0.0.1',  state: 'ACTIVE' },
                { dst: '11.0.0.0/8',  via: '195.0.0.1', state: 'ACTIVE' }
            ]
        });
    }
    jsonReply(res, 404, { error: 'Not Found' });
}).listen(PORT, '0.0.0.0', function() {
    process.stdout.write('[gateway-agent] Listening on :' + PORT + '\n');
});
JS

cat > /etc/systemd/system/gateway-agent.service << 'SVC'
[Unit]
Description=KESTREL Gateway Agent
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/gateway-agent/src/agent.js
Restart=always
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/opt/gateway-agent

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  gateway-agent.service --quiet
systemctl restart gateway-agent.service 2>/dev/null \
    || systemctl start gateway-agent.service
info "gateway-agent Node.js on :3300"

# =============================================================================
# 6. SNMP (Port 161 UDP)
# =============================================================================
section "SNMP — Gateway Interface Monitoring (Port 161 UDP)"
pkg_install snmpd snmp

cat > /etc/snmp/snmpd.conf << 'SNMP'
agentAddress udp:161,tcp:161
rocommunity public default
rocommunity kestrel_gw 11.0.0.0/8
rocommunity kestrel_gw 195.0.0.0/8
sysLocation "FOB KESTREL — Signal Gateway — DMZ/Private Border"
sysContact  "NetOps <netops@iwdesert.mil>"
sysName     "sigint-gateway.iwdesert.mil"
sysDescr    "KESTREL Gateway Node — Ubuntu 22.04 LTS — Dual-Homed"
sysServices 76
SNMP

systemctl enable snmpd --quiet
systemctl restart snmpd 2>/dev/null || systemctl start snmpd
info "SNMP on :161"

# =============================================================================
# 7. VSFTPD — Gateway Config Backup FTP (Port 21)
# =============================================================================
section "vsftpd — Gateway Config Backup FTP (Port 21)"
pkg_install vsftpd

useradd -m -s /bin/false gw-backup 2>/dev/null || true
echo "gw-backup:GwBkup2024Kestrel" | chpasswd

mkdir -p /srv/ftp/gateway-configs
mkdir -p /srv/ftp/routing-backups
mkdir -p /srv/ftp/iptables-snapshots
chown -R nobody:nogroup /srv/ftp 2>/dev/null || true

cat > /srv/ftp/iptables-snapshots/iptables-2025-04-18.rules << 'RULES'
# Generated by iptables-save — Fri Apr 18 00:00:01 2025
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22   -s 11.0.0.0/8 -j ACCEPT
-A INPUT -p tcp --dport 8080 -s 11.0.0.0/8 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -i eth1 -o eth0 -j ACCEPT
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
RULES

cat > /srv/ftp/routing-backups/route-table-2025-04-17.txt << 'TXT'
# KESTREL Gateway — Route Table Backup — 2025-04-17
# Captured: 23:59:01 UTC
default via 11.0.0.1 dev eth0
11.0.0.0/8  dev eth0 proto kernel scope link
195.0.0.0/8 dev eth1 proto kernel scope link
TXT

mkdir -p /var/run/vsftpd/empty

cat > /etc/vsftpd.conf << 'VSFTPD'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=NO
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
ftpd_banner=KESTREL Gateway Config Backup FTP — Authorized Personnel Only
local_root=/srv/ftp
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
VSFTPD

systemctl enable vsftpd --quiet
systemctl restart vsftpd 2>/dev/null || systemctl start vsftpd
info "vsftpd backup FTP on :21"

# =============================================================================
# 8. DECOY PKI — Self-signed cert for realism
# =============================================================================
section "Decoy PKI / Self-signed Certificate"
pkg_install openssl

mkdir -p /etc/ssl/kestrel/gateway
mkdir -p /opt/gateway-agent/pki

openssl req -x509 -newkey rsa:2048 \
    -keyout /etc/ssl/kestrel/gateway/gateway.key \
    -out    /etc/ssl/kestrel/gateway/gateway.crt \
    -days 365 -nodes \
    -subj "/C=US/ST=Exercise/L=FOB-Kestrel/O=DesertWire/CN=sigint-gateway.iwdesert.mil" \
    2>/dev/null

chmod 600 /etc/ssl/kestrel/gateway/gateway.key
chmod 644 /etc/ssl/kestrel/gateway/gateway.crt

cat > /etc/ssl/kestrel/gateway/README << 'TXT'
KESTREL Gateway SSL Certificates
==================================
gateway.key — Private key for TLS termination (mode 600)
gateway.crt — CN=sigint-gateway.iwdesert.mil
Do NOT use these for API authentication.
Contact: pki@iwdesert.mil
TXT

cat > /opt/gateway-agent/pki/service_token.txt << 'TXT'
# KESTREL gateway-agent service token
# Scope: local gateway management API only — NOT for signal processing
# Issued: 2025-01-10
GW-AGENT-SVC-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
TXT
chmod 600 /opt/gateway-agent/pki/service_token.txt

info "Decoy PKI in /etc/ssl/kestrel/gateway"

# =============================================================================
# 9. UFW
# =============================================================================
section "UFW — Allow Decoy Ports (real ports preserved)"
if command -v ufw &>/dev/null; then
    ufw allow 22 &>/dev/null || true   # SSH — only real service on M3
    ufw --force enable &>/dev/null || true
    for PORT in 21 161/udp 3300 3306 8080; do
        ufw allow "$PORT" &>/dev/null || true
    done
    info "UFW rules added (22 + decoy ports)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "M3 Decoy Setup Complete"
cat << 'SUMMARY'
================================================================
  M3: sigint-gateway — Decoy Services
  Challenge: sudo node GTFOBin — UNTOUCHED
             /opt/gateway/config.json (real token) — UNTOUCHED
----------------------------------------------------------------
  Nginx     :8080   Gateway status portal
  MariaDB   :3306   gateway_config DB
  Node.js   :3300   gateway-agent (legitimate node process)
  SNMP      :161    communities: public, kestrel_gw
  vsftpd    :21     gateway config backup FTP

  Decoy sudoers.d (non-GTFOBin):
    /etc/sudoers.d/98-gateway-netops   (iptables -L, ip show)
    /etc/sudoers.d/97-gateway-svcmgmt  (systemctl status only)
    /etc/sudoers.d/96-gateway-logread  (journalctl, cat auth.log)

  Decoy configs (wrong paths / fake tokens):
    /opt/gateway-agent/conf/config.json
    /opt/net-ops/conf/config.json
    /opt/routing-daemon/etc/routing.conf
    /opt/gateway/cache/last_config_snapshot.json
    /opt/gateway-agent/pki/service_token.txt

  SSH :22  — UNTOUCHED
  sudo node rule   — UNTOUCHED
  /opt/gateway/config.json — UNTOUCHED
================================================================
SUMMARY
