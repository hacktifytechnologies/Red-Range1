#!/usr/bin/env bash
# =============================================================================
#  DECOY SETUP — M1: sigint-relay  (v2 — fully fixed)
#  Challenge : Node.js Express SSRF on Port 80
#  Networks  : v-Pub + v-DMZ
#  NEVER TOUCH: Port 22 (SSH), Port 80 (real Node.js app)
#  Run as   : sudo bash M1-decoy-sigint-relay.sh
# =============================================================================
# BUGS FIXED vs v1:
#   1. nginx: stop→reset-failed→rm default site→rm conf.d→configure→start
#      (was: only rm default, then restart — failed because apt auto-started
#       nginx in a failed state which persisted through restart)
#   2. Apache: stop→reset-failed→a2dissite→sed 'Listen 80' OUT of ports.conf
#      →add only our ports→configure→start
#      (was: a2dissite 000-default left "Listen 80" in ports.conf so Apache
#       still tried to bind port 80 even with no vhost using it)
#   3. mkdir -p created for EVERY api subdirectory before any cat > redirect
#      (was: /api/ created but /api/uplink/, /api/scheduler/, /api/health/
#       not created — caused "No such file or directory" at line 117)
#   4. Postfix pre-seeded with debconf-set-selections before install
#      (was: interactive prompt on fresh Ubuntu 22.04)
#   5. All systemctl use 'start' not 'restart' after fresh config
#      (was: 'restart' on a never-started or failed service can misfire)
#   6. All service ops wrapped with "|| true" where failure is acceptable
# =============================================================================

set -euo pipefail
LOG="/root/decoy_setup_log_M1.txt"
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

# ── nginx safe-install helper ─────────────────────────────────────────────────
# After apt installs nginx it auto-starts (or enters failed state if port 80
# is taken). We stop it, clear the failure record, strip every default config
# that binds port 80, then let the caller add custom sites and call start.
nginx_prepare() {
    pkg_install nginx
    systemctl stop nginx 2>/dev/null || true
    systemctl reset-failed nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/conf.d/*.conf 2>/dev/null || true
}

# ── Apache safe-install helper ────────────────────────────────────────────────
# Ubuntu's ports.conf has "Listen 80". Even after disabling the default vhost,
# Apache still binds every port in ports.conf. We must remove "Listen 80"
# explicitly, then add only the ports our decoy vhosts actually use.
apache_prepare() {
    pkg_install apache2
    systemctl stop apache2 2>/dev/null || true
    systemctl reset-failed apache2 2>/dev/null || true
    a2dissite 000-default 2>/dev/null || true
    a2enmod headers rewrite 2>/dev/null || true
    # Strip the two default Listen lines so Apache never tries port 80 or 443
    sed -i '/^Listen 80\s*$/d'  /etc/apache2/ports.conf
    sed -i '/^Listen 443\s*$/d' /etc/apache2/ports.conf
}

# =============================================================================
# 1. NGINX — Relay Ops Portal (Port 8443)
# =============================================================================
section "Nginx — Relay Ops Portal (Port 8443)"

nginx_prepare

# Create ALL parent directories BEFORE any cat > redirect
mkdir -p /var/www/html/relay-portal/api/uplink
mkdir -p /var/www/html/relay-portal/api/scheduler
mkdir -p /var/www/html/relay-portal/api/health
mkdir -p /var/www/html/relay-portal/liaison
mkdir -p /var/www/html/relay-portal/admin

cat > /var/www/html/relay-portal/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>KESTREL Relay Ops Portal — iwdesert.mil</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#0d0d0d;color:#c5c5c5;font-family:'Courier New',monospace}
    header{background:#111;border-bottom:2px solid #2a6b3a;padding:14px 24px;
           display:flex;justify-content:space-between;align-items:center}
    header h1{font-size:1.1rem;color:#4caf50;letter-spacing:2px}
    header span{font-size:.75rem;color:#888}
    .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;padding:28px}
    .card{background:#161616;border:1px solid #2a2a2a;border-radius:4px;padding:20px}
    .card h3{font-size:.85rem;color:#4caf50;margin-bottom:10px;
             text-transform:uppercase;letter-spacing:1px}
    .card p{font-size:.8rem;color:#888;line-height:1.6}
    .card a{color:#5bc0de;font-size:.8rem;text-decoration:none;
            display:block;margin-top:10px}
    .badge{display:inline-block;padding:2px 8px;border-radius:2px;
           font-size:.7rem;margin-top:6px}
    .ok{background:#1a3a1a;color:#4caf50}
    .warn{background:#3a2a00;color:#ffc107}
    footer{text-align:center;padding:16px;font-size:.7rem;color:#444;
           border-top:1px solid #1e1e1e}
  </style>
</head>
<body>
<header>
  <h1>⚡ KESTREL RELAY OPS PORTAL</h1>
  <span>UNCLASSIFIED // EXERCISE ONLY // iwdesert.mil</span>
</header>
<div class="grid">
  <div class="card">
    <h3>Uplink Status</h3>
    <p>Primary: FOB-ALPHA — NOMINAL<br>Secondary: FOB-BRAVO — DEGRADED</p>
    <span class="badge warn">1 Node Degraded</span>
    <a href="/api/uplink/status">→ Uplink Status API</a>
  </div>
  <div class="card">
    <h3>Frequency Scheduler</h3>
    <p>Next rotation: 06:00Z<br>Bands: 30-88 MHz, 225-400 MHz</p>
    <span class="badge ok">Scheduler Active</span>
    <a href="/api/scheduler/active">→ Scheduler API</a>
  </div>
  <div class="card">
    <h3>Relay Health</h3>
    <p>Nodes reporting: 4/5<br>Last heartbeat: 2 min ago</p>
    <span class="badge warn">relay-node-04 Silent</span>
    <a href="/api/health/nodes">→ Health API</a>
  </div>
  <div class="card">
    <h3>Liaison Officer Portal</h3>
    <p>Submit frequency schedules.<br>Check uplink status.</p>
    <span class="badge ok">Online</span>
    <a href="/liaison/">→ Liaison Login</a>
  </div>
  <div class="card">
    <h3>Admin Console</h3>
    <p>System configuration.<br>Operator management.</p>
    <span class="badge warn">Restricted</span>
    <a href="/admin/">→ Admin Login</a>
  </div>
  <div class="card">
    <h3>Collection Tasking</h3>
    <p>Active tasks: 14<br>Pending review: 3</p>
    <span class="badge ok">Nominal</span>
    <a href="/api/health/nodes">→ Node Health</a>
  </div>
</div>
<footer>Operations Support Cell — FOB KESTREL — Contact: noc@iwdesert.mil</footer>
</body>
</html>
HTML

cat > /var/www/html/relay-portal/api/uplink/status << 'JSON'
{
  "timestamp": "2025-04-18T04:00:00Z",
  "nodes": [
    {"id":"relay-node-01","region":"FOB-ALPHA","status":"UP",      "latency_ms":12},
    {"id":"relay-node-02","region":"FOB-ALPHA","status":"UP",      "latency_ms":14},
    {"id":"relay-node-03","region":"FOB-BRAVO","status":"DEGRADED","latency_ms":340},
    {"id":"relay-node-04","region":"FOB-BRAVO","status":"SILENT",  "latency_ms":null},
    {"id":"relay-node-05","region":"RESERVE",  "status":"UP",      "latency_ms":8}
  ],
  "overall": "DEGRADED"
}
JSON

cat > /var/www/html/relay-portal/api/scheduler/active << 'JSON'
{
  "schedule_id":  "SCH-2025-0418-001",
  "operator":     "liaison_ops",
  "active_bands": ["30-88 MHz","225-400 MHz","1350-1850 MHz"],
  "next_rotation":"2025-04-18T06:00:00Z",
  "tasked_by":    "JCOC"
}
JSON

cat > /var/www/html/relay-portal/api/health/nodes << 'JSON'
{
  "checked_at":     "2025-04-18T04:01:00Z",
  "nodes_total":    5,
  "nodes_ok":       3,
  "nodes_warn":     1,
  "nodes_critical": 1
}
JSON

cat > /var/www/html/relay-portal/liaison/index.html << 'HTML'
<!DOCTYPE html><html><head><title>Liaison Portal — iwdesert.mil</title>
<style>
body{background:#0f1117;color:#c5c5c5;font-family:sans-serif;
     display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
.box{background:#161b22;border:1px solid #30363d;padding:40px;
     width:340px;border-radius:6px}
h2{color:#58a6ff;margin-bottom:6px}
p{color:#8b949e;font-size:.85rem;margin-bottom:20px}
input{width:100%;padding:9px 12px;background:#0d1117;border:1px solid #30363d;
      color:#c9d1d9;border-radius:4px;margin:6px 0;box-sizing:border-box}
button{width:100%;padding:10px;background:#1f6feb;border:none;color:#fff;
       border-radius:4px;cursor:pointer;font-weight:600;margin-top:8px}
small{display:block;text-align:center;margin-top:14px;color:#666;font-size:.75rem}
</style></head><body>
<div class="box">
  <h2>Liaison Officer Portal</h2>
  <p>Frequency schedule submission &amp; uplink verification</p>
  <input type="text" placeholder="Liaison ID">
  <input type="password" placeholder="Access Code">
  <button>Authenticate</button>
  <small>Unauthorized access violates FOB KESTREL ROE</small>
</div></body></html>
HTML

cat > /var/www/html/relay-portal/admin/index.html << 'HTML'
<!DOCTYPE html><html><head><title>Admin — Relay Ops</title>
<style>
body{background:#161b22;color:#c9d1d9;font-family:sans-serif;
     display:flex;justify-content:center;align-items:center;height:100vh;margin:0}
.box{background:#0d1117;border:1px solid #f85149;padding:40px;
     width:340px;border-radius:6px}
h2{color:#f85149;margin-bottom:6px}
p{color:#8b949e;font-size:.85rem;margin-bottom:20px}
input{width:100%;padding:9px 12px;background:#161b22;border:1px solid #30363d;
      color:#c9d1d9;border-radius:4px;margin:6px 0;box-sizing:border-box}
button{width:100%;padding:10px;background:#da3633;border:none;color:#fff;
       border-radius:4px;cursor:pointer;font-weight:600;margin-top:8px}
small{display:block;text-align:center;margin-top:14px;color:#666;font-size:.75rem}
</style></head><body>
<div class="box">
  <h2>&#9888; Admin Console</h2>
  <p>System administration — restricted to NOC personnel only</p>
  <input type="text" placeholder="Admin Username">
  <input type="password" placeholder="Admin Password">
  <button>Login</button>
  <small>All access attempts are logged and audited</small>
</div></body></html>
HTML

# Nginx site — port 8443 ONLY, no mention of port 80 anywhere
cat > /etc/nginx/sites-available/relay-portal << 'NGINX'
server {
    listen 8443 default_server;
    root /var/www/html/relay-portal;
    index index.html;
    server_name _;

    add_header X-Powered-By "KESTREL-OPS/2.3" always;

    location /api/ {
        default_type application/json;
        try_files $uri $uri/ =404;
    }
    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/relay-portal-access.log;
    error_log  /var/log/nginx/relay-portal-error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/relay-portal \
       /etc/nginx/sites-enabled/relay-portal

nginx -t
systemctl enable nginx --quiet
systemctl start nginx      # 'start' not 'restart' — fresh config, never ran cleanly
info "Nginx relay portal on :8443"

# =============================================================================
# 2. APACHE2 — Comms Ops Dashboard :8080 + Tomcat Lookalike :8090
# =============================================================================
section "Apache2 — Comms Ops Dashboard :8080 + Tomcat Lookalike :8090"

apache_prepare   # stops apache, removes Listen 80 from ports.conf

grep -q "Listen 8080" /etc/apache2/ports.conf || echo "Listen 8080" >> /etc/apache2/ports.conf
grep -q "Listen 8090" /etc/apache2/ports.conf || echo "Listen 8090" >> /etc/apache2/ports.conf

mkdir -p /var/www/html/comms-ops/api
mkdir -p /var/www/html/tomcat-fake/manager

cat > /var/www/html/comms-ops/index.html << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>COMMS-OPS Internal Dashboard</title>
<style>
body{background:#1a1a2e;color:#e0e0e0;font-family:monospace;margin:0}
nav{background:#16213e;padding:12px 20px;border-bottom:2px solid #0f3460}
nav span{color:#e94560;font-weight:bold;font-size:1.1em}
.content{padding:24px}
table{width:100%;border-collapse:collapse;font-size:.85em}
th{background:#0f3460;color:#e0e0e0;padding:10px;text-align:left}
td{padding:9px;border-bottom:1px solid #2a2a4a}
tr:hover td{background:#1e1e3e}
.up{color:#4caf50}.down{color:#f44336}.deg{color:#ff9800}
</style></head><body>
<nav><span>COMMS-OPS</span> &nbsp;|&nbsp; Internal Relay Status
&nbsp;|&nbsp;<small style="color:#888">iwdesert.mil</small></nav>
<div class="content">
  <h2 style="color:#e94560;margin-bottom:16px">Relay Node Status</h2>
  <table>
    <tr><th>Node ID</th><th>Region</th><th>Service</th><th>Status</th><th>Last Seen</th></tr>
    <tr><td>relay-node-01</td><td>FOB-ALPHA</td><td>SIGINT Relay</td>
        <td class="up">UP</td><td>12s ago</td></tr>
    <tr><td>relay-node-02</td><td>FOB-ALPHA</td><td>SIGINT Relay</td>
        <td class="up">UP</td><td>14s ago</td></tr>
    <tr><td>relay-node-03</td><td>FOB-BRAVO</td><td>SIGINT Relay</td>
        <td class="deg">DEGRADED</td><td>6 min ago</td></tr>
    <tr><td>relay-node-04</td><td>FOB-BRAVO</td><td>SIGINT Relay</td>
        <td class="down">SILENT</td><td>22 min ago</td></tr>
    <tr><td>monitor-01</td><td>DMZ</td><td>Signal Monitor</td>
        <td class="up">UP</td><td>8s ago</td></tr>
  </table>
  <p style="margin-top:20px;color:#888;font-size:.8em">
    Auto-refresh: 60s | Contact: noc@iwdesert.mil</p>
</div></body></html>
HTML

cat > /var/www/html/comms-ops/api/nodes.json << 'JSON'
{"nodes":["relay-node-01","relay-node-02","relay-node-03","relay-node-04","monitor-01"],
 "healthy":3,"degraded":1,"silent":1}
JSON

cat > /var/www/html/comms-ops/api/config.json << 'JSON'
{"app":"comms-ops-dashboard","version":"1.8.2","environment":"production",
 "refresh_interval_sec":60,"contact":"noc@iwdesert.mil"}
JSON

cat > /var/www/html/tomcat-fake/index.html << 'HTML'
<!DOCTYPE html><html><head><title>Apache Tomcat/9.0.80</title>
<style>body{font-family:sans-serif;background:#fff;margin:0}
.hdr{background:#6d4c9f;color:#fff;padding:20px}
.box{border:1px solid #ddd;padding:15px;margin:20px;background:#f8f8f8;border-radius:4px}
</style></head><body>
<div class="hdr"><h1>Apache Tomcat/9.0.80</h1><p>Desert Wire App Server</p></div>
<div class="box"><h3>Applications</h3><ul>
  <li><a href="/sigint-webapp/">SIGINT Web Application</a> — Running</li>
  <li><a href="/manager/html">Manager App</a> — Restricted</li>
  <li><a href="/host-manager/">Host Manager</a> — Restricted</li>
</ul></div>
<div class="box"><h3>Server Info</h3>
  <p>JVM: OpenJDK 17.0.8 | OS: Linux 5.15 | Servlet: 4.0</p></div>
</body></html>
HTML

cat > /var/www/html/tomcat-fake/manager/index.html << 'HTML'
<!DOCTYPE html><html><head><title>Tomcat Manager — Auth Required</title></head><body>
<h2>401 Unauthorized</h2>
<p>Manager application requires authentication.<br>
Contact the system administrator for credentials.</p>
</body></html>
HTML

cat > /etc/apache2/sites-available/decoy-vhosts.conf << 'APACHECONF'
<VirtualHost *:8080>
    DocumentRoot /var/www/html/comms-ops
    DirectoryIndex index.html
    Options -Indexes
    Header always set Server "Apache/2.4 KESTREL-NOC"
    Header always set X-Application "COMMS-OPS-DASH/1.8.2"
    <Location /api/>
        Header set Content-Type "application/json"
    </Location>
    ErrorLog  ${APACHE_LOG_DIR}/comms-ops-error.log
    CustomLog ${APACHE_LOG_DIR}/comms-ops-access.log combined
</VirtualHost>

<VirtualHost *:8090>
    DocumentRoot /var/www/html/tomcat-fake
    DirectoryIndex index.html
    Options -Indexes
    Header always set Server "Apache-Coyote/1.1"
    Header always set X-Powered-By "Servlet/4.0 (Apache Tomcat/9.0.80 Java/17)"
    ErrorLog  ${APACHE_LOG_DIR}/tomcat-error.log
    CustomLog ${APACHE_LOG_DIR}/tomcat-access.log combined
</VirtualHost>
APACHECONF

a2ensite decoy-vhosts.conf 2>/dev/null || true
systemctl enable apache2 --quiet
systemctl start apache2
info "Apache2 comms-ops on :8080, tomcat-fake on :8090"

# =============================================================================
# 3. VSFTPD — Relay Config FTP (Port 21)
# =============================================================================
section "vsftpd — Relay Config FTP (Port 21)"
pkg_install vsftpd

useradd -m -s /bin/false relay-ftp 2>/dev/null || true
echo "relay-ftp:R3layFtp@K3strel!" | chpasswd

mkdir -p /srv/ftp/relay-configs
mkdir -p /srv/ftp/frequency-tables
mkdir -p /srv/ftp/firmware-updates
chown -R nobody:nogroup /srv/ftp 2>/dev/null || true

cat > /srv/ftp/relay-configs/relay-node-01.conf << 'CONF'
# Relay Node 01 — FOB-ALPHA Primary
[node]
node_id     = relay-node-01
region      = FOB-ALPHA
uplink_url  = http://relay-ops.iwdesert.mil/uplink
heartbeat_s = 30
retry_count = 5
[crypto]
protocol    = TLS1.3
[logging]
level       = INFO
syslog      = yes
CONF

cat > /srv/ftp/relay-configs/relay-node-02.conf << 'CONF'
# Relay Node 02 — FOB-ALPHA Secondary
[node]
node_id     = relay-node-02
region      = FOB-ALPHA
uplink_url  = http://relay-ops.iwdesert.mil/uplink
heartbeat_s = 30
retry_count = 5
[crypto]
protocol    = TLS1.3
[logging]
level       = INFO
syslog      = yes
CONF

cat > /srv/ftp/frequency-tables/band-schedule-2025-04.txt << 'TXT'
# DESERT WIRE — Frequency Band Schedule — April 2025
# Classification: UNCLASSIFIED // EXERCISE
Band      | Start MHz | End MHz | Rotation UTC | Node
ALPHA-LO  | 30        | 88      | 00:00        | relay-node-01
ALPHA-HI  | 225       | 400     | 06:00        | relay-node-02
BRAVO-LO  | 30        | 88      | 12:00        | relay-node-03
BRAVO-HI  | 1350      | 1850    | 18:00        | relay-node-04
TXT

cat > /srv/ftp/firmware-updates/README.txt << 'TXT'
Relay Node Firmware Updates
===========================
Bundles must be GPG-signed with the KESTREL infrastructure key.
Contact: infra@iwdesert.mil
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
ftpd_banner=FOB KESTREL Relay Config FTP — Authorized Personnel Only
anon_root=/srv/ftp
local_root=/srv/ftp
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
VSFTPD

systemctl enable vsftpd --quiet
systemctl restart vsftpd 2>/dev/null || systemctl start vsftpd
info "vsftpd relay config FTP on :21"

# =============================================================================
# 4. SNMP — Relay Node Monitoring (Port 161 UDP)
# =============================================================================
section "SNMP — Relay Node Monitoring (Port 161 UDP)"
pkg_install snmpd snmp

cat > /etc/snmp/snmpd.conf << 'SNMP'
agentAddress udp:161,tcp:161
rocommunity public default
rocommunity kestrel_noc 10.0.0.0/8
sysLocation "FOB KESTREL — Relay Ops Cell — Sector 7"
sysContact  "NOC Team <noc@iwdesert.mil>"
sysName     "sigint-relay.iwdesert.mil"
sysDescr    "KESTREL Relay Node — Ubuntu 22.04 LTS"
sysServices 72
SNMP

systemctl enable snmpd --quiet
systemctl restart snmpd 2>/dev/null || systemctl start snmpd
info "SNMP on UDP/TCP :161"

# =============================================================================
# 5. POSTFIX — Relay Alert Mailer (Ports 25, 587)
#    Pre-seed debconf to prevent interactive prompts on Ubuntu 22.04
# =============================================================================
section "Postfix — Relay Alert Mailer (Ports 25/587)"

debconf-set-selections <<< "postfix postfix/mailname string sigint-relay.iwdesert.mil"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

pkg_install postfix

postconf -e "myhostname = sigint-relay.iwdesert.mil"
postconf -e "myorigin = /etc/mailname"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mynetworks = 127.0.0.0/8 11.0.0.0/8"
postconf -e "smtpd_banner = \$myhostname ESMTP KESTREL-RELAY-MAILER"
postconf -e "relayhost ="
echo "sigint-relay.iwdesert.mil" > /etc/mailname

systemctl enable postfix --quiet
systemctl restart postfix 2>/dev/null || systemctl start postfix
info "Postfix on :25/:587"

# =============================================================================
# 6. RSYSLOG — Central Log Collector (Port 514 TCP/UDP)
# =============================================================================
section "Rsyslog — Central Log Collector (Port 514)"
pkg_install rsyslog

cat > /etc/rsyslog.d/49-relay-remote.conf << 'RSYSLOG'
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
$template NodeLogs,"/var/log/relay-nodes/%HOSTNAME%/syslog.log"
if $fromhost-ip != '127.0.0.1' then ?NodeLogs
RSYSLOG

mkdir -p /var/log/relay-nodes/relay-node-01

cat > /var/log/relay-nodes/relay-node-01/syslog.log << 'LOG'
Apr 18 03:14:22 relay-node-01 relay-agent[1234]: heartbeat OK — latency 12ms
Apr 18 03:15:22 relay-node-01 relay-agent[1234]: heartbeat OK — latency 11ms
Apr 18 03:44:01 relay-node-01 relay-agent[1234]: band rotation — ALPHA-LO active
Apr 18 04:00:00 relay-node-01 relay-agent[1234]: heartbeat OK — latency 13ms
LOG

systemctl restart rsyslog
info "Rsyslog on UDP/TCP :514"

# =============================================================================
# 7. DECOY CONFIG FILES
# =============================================================================
section "Decoy Config and Env Files"

mkdir -p /opt/relay-agent/conf
mkdir -p /opt/relay-ops/etc
mkdir -p /etc/kestrel/ssl
mkdir -p /usr/local/bin

cat > /opt/relay-agent/conf/.env << 'ENV'
# Relay Agent — Environment Configuration
NODE_ENV=production
PORT=3100
LOG_LEVEL=info
HEALTH_ENDPOINT=http://127.0.0.1:3100/health
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=relay_agent_db
DB_USER=relay_agent
DB_PASS=AgentDB@K3strel99
SMTP_HOST=127.0.0.1
SMTP_PORT=25
SMTP_FROM=relay-agent@iwdesert.mil
COMMS_OPS_API_KEY=KESTREL-RELAY-API-0000-0000-0000
ENV
chmod 640 /opt/relay-agent/conf/.env

cat > /opt/relay-ops/etc/relay.conf << 'CONF'
[relay]
service_name      = kestrel-relay-ops
bind_port         = 3100
workers           = 4
[upstream]
poll_interval_sec = 30
node_list_url     = http://127.0.0.1:3100/internal/nodes
[auth]
session_secret    = SESS-RELAY-XXXXXXXXXXXXXXXXXXXXXXXX
token_validity    = 3600
[database]
host = 127.0.0.1
port = 5432
name = relay_ops
user = relay_db
pass = RelayDB_K3str3l_9
[logging]
access_log = /var/log/desertrelay.log
level      = info
CONF
chmod 640 /opt/relay-ops/etc/relay.conf

cat > /etc/kestrel/ssl/README << 'TXT'
KESTREL Relay SSL Certificates
================================
relay.iwdesert.mil.crt — Public certificate
relay.iwdesert.mil.key — Private key (mode 600)
Issued by: KESTREL-PKI Internal CA
Contact: pki@iwdesert.mil
TXT

cat > /usr/local/bin/relay-sync.sh << 'SH'
#!/bin/bash
logger -t relay-sync "Config sync heartbeat — OK"
SH
chmod +x /usr/local/bin/relay-sync.sh

cat > /etc/cron.d/relay-sync << 'CRON'
*/15 * * * * root /usr/local/bin/relay-sync.sh >> /var/log/relay-sync.log 2>&1
CRON

info "Decoy configs in /opt/relay-agent, /opt/relay-ops, /etc/kestrel"

# =============================================================================
# 8. SOCAT DECOY LISTENERS (Ports 9100, 3100, 4000)
# =============================================================================
section "Socat Decoy Listeners (Ports 9100, 3100, 4000)"
pkg_install socat

# Build decoy scripts and systemd units from an associative array.
# Note: banners use \r\n for HTTP compliance; inner \n is literal newline.
declare -A DECOYS
DECOYS[9100]='HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\n# HELP node_cpu_seconds_total CPU\n# TYPE node_cpu_seconds_total counter\nnode_cpu_seconds_total{cpu="0",mode="idle"} 3.94e+08\n'
DECOYS[3100]='HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{"status":"ok","service":"relay-agent","version":"2.1.0"}\r\n'
DECOYS[4000]='HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{"service":"relay-webhook","ready":true}\r\n'

for PORT in "${!DECOYS[@]}"; do
    BANNER="${DECOYS[$PORT]}"

    cat > /usr/local/bin/decoy-m1-${PORT}.sh << SOCAT
#!/bin/bash
while true; do
    printf '${BANNER}' | socat TCP-LISTEN:${PORT},reuseaddr,fork STDIN 2>/dev/null \
        || sleep 2
done
SOCAT
    chmod +x /usr/local/bin/decoy-m1-${PORT}.sh

    cat > /etc/systemd/system/decoy-m1-${PORT}.service << SVC
[Unit]
Description=M1 Decoy Listener Port ${PORT}
After=network.target

[Service]
ExecStart=/usr/local/bin/decoy-m1-${PORT}.sh
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC
done

systemctl daemon-reload
for PORT in "${!DECOYS[@]}"; do
    systemctl enable  decoy-m1-${PORT}.service --quiet
    systemctl restart decoy-m1-${PORT}.service 2>/dev/null \
        || systemctl start decoy-m1-${PORT}.service
done
info "Socat decoys: :9100 (node-exporter) :3100 (relay-agent) :4000 (webhook)"

# =============================================================================
# 9. UFW
# =============================================================================
section "UFW — Allow Decoy Ports (real ports preserved)"
if command -v ufw &>/dev/null; then
    # CRITICAL: allow SSH and the real app port FIRST — before enabling the firewall.
    # Without these, ufw --force enable would block port 80 (real Node.js app)
    # and port 22 (SSH) from outside the machine.
    ufw allow 22  &>/dev/null || true   # SSH  — must always be open
    ufw allow 80  &>/dev/null || true   # real Node.js SSRF challenge — must stay open
    ufw --force enable &>/dev/null || true
    for PORT in 21 25 161/udp 514 587 3100 4000 8080 8090 8443 9100; do
        ufw allow "$PORT" &>/dev/null || true
    done
    info "UFW rules added (22 + 80 + decoy ports)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "M1 Decoy Setup Complete"
cat << 'SUMMARY'
================================================================
  M1: sigint-relay — Decoy Services
  Challenge: SSRF on Node.js (Port 80 — UNTOUCHED)
----------------------------------------------------------------
  Nginx  :8443   Relay Ops Portal (uplink/scheduler/health APIs)
  Apache :8080   Comms Ops Dashboard
  Apache :8090   Tomcat 9 lookalike
  vsftpd :21     Relay config FTP
  SNMP   :161    communities: public, kestrel_noc
  Postfix :25/587 Relay alert mailer
  Rsyslog :514   Central log collector
  Socat  :9100   node-exporter lookalike
  Socat  :3100   relay-agent API lookalike
  Socat  :4000   relay-webhook lookalike

  SSH :22  — UNTOUCHED
  App :80  — UNTOUCHED
================================================================
SUMMARY
