#!/usr/bin/env bash
# =============================================================================
#  DECOY SETUP — M2: sigint-monitor  (v2 — fully fixed)
#  Challenge : Python Flask OS Command Injection on Port 8080
#  Network   : v-DMZ only
#  NEVER TOUCH: Port 22 (SSH), Port 8080 (real Flask app),
#               /opt/monitor/keys/ (real SSH key for M3 pivot)
#  Run as   : sudo bash M2-decoy-sigint-monitor.sh
# =============================================================================
# BUGS FIXED vs v1:
#   1. nginx_prepare(): stop→reset-failed→rm default→rm conf.d before config
#   2. apache_prepare(): stop→reset-failed→a2dissite→sed Listen 80 OUT of
#      ports.conf before adding our ports
#   3. mkdir -p for EVERY file's parent directory before cat > redirect
#   4. All systemctl ops use 'start' not 'restart' after fresh config
#   5. Python Prometheus service: ExecStart path validated, uses python3
#   6. Redis: proper sed guard, password without shell-special chars that
#      could cause issues in double-quoted echo
# =============================================================================

set -euo pipefail
LOG="/root/decoy_setup_log_M2.txt"
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

apache_prepare() {
    pkg_install apache2
    systemctl stop apache2 2>/dev/null || true
    systemctl reset-failed apache2 2>/dev/null || true
    a2dissite 000-default 2>/dev/null || true
    a2enmod headers 2>/dev/null || true
    # Remove Listen 80 and 443 — we don't use them; prevents accidental bind
    sed -i '/^Listen 80\s*$/d'  /etc/apache2/ports.conf
    sed -i '/^Listen 443\s*$/d' /etc/apache2/ports.conf
}

# =============================================================================
# 1. NGINX — Grafana Dashboard Lookalike (Port 3000)
#    M2 has Flask on 8080. Port 80 is FREE here, but we don't want or need it.
# =============================================================================
section "Nginx — Grafana Lookalike (Port 3000)"

nginx_prepare

mkdir -p /var/www/html/grafana-fake/api
mkdir -p /var/www/html/grafana-fake/dashboards

cat > /var/www/html/grafana-fake/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Grafana — KESTREL Signal Metrics</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#111217;color:#d8d9da;font-family:-apple-system,sans-serif}
    .sidenav{width:56px;position:fixed;top:0;left:0;height:100%;
             background:#181b1f;border-right:1px solid #22252b;
             display:flex;flex-direction:column;align-items:center;
             padding:12px 0;gap:20px;z-index:10}
    .sidenav span{font-size:18px;cursor:pointer;color:#6e9fff}
    .topbar{margin-left:56px;background:#181b1f;border-bottom:1px solid #22252b;
            padding:10px 20px;display:flex;justify-content:space-between;
            align-items:center}
    .topbar h2{font-size:.95rem;color:#d8d9da}
    .topbar small{font-size:.75rem;color:#6c7280}
    .panels{margin-left:56px;padding:20px;display:grid;
            grid-template-columns:repeat(2,1fr);gap:16px}
    .panel{background:#1c1f26;border:1px solid #22252b;border-radius:4px;padding:16px}
    .panel h3{font-size:.8rem;color:#8e9cb2;text-transform:uppercase;
              letter-spacing:1px;margin-bottom:12px}
    .metric{font-size:2.2rem;font-weight:300;color:#73bf69}
    .sub{font-size:.75rem;color:#6c7280;margin-top:4px}
    .bar{height:8px;background:#2a2e3a;border-radius:4px;margin:8px 0}
    .bar-fill{height:8px;border-radius:4px;background:#5794f2}
    footer{margin-left:56px;padding:10px 20px;font-size:.7rem;color:#444;
           border-top:1px solid #22252b}
  </style>
</head>
<body>
<div class="sidenav">
  <span>&#8862;</span><span>&#9889;</span><span>&#128202;</span>
  <span>&#128276;</span><span>&#9881;</span>
</div>
<div class="topbar">
  <h2>&#128225; KESTREL Signal Collection — Node Health Overview</h2>
  <small>Datasource: Prometheus | Refresh: 30s | Last: just now</small>
</div>
<div class="panels">
  <div class="panel">
    <h3>Signal Intercept Rate (last 1h)</h3>
    <div class="metric">47,293 <span style="font-size:1rem">pkt/s</span></div>
    <div class="sub">&#8593; 3.2% from last hour</div>
  </div>
  <div class="panel">
    <h3>Active Collection Nodes</h3>
    <div class="metric" style="color:#5794f2">4 / 5</div>
    <div class="sub">relay-node-04 — SILENT</div>
  </div>
  <div class="panel">
    <h3>CPU Utilisation</h3>
    <div class="metric" style="color:#ff9830">63.4%</div>
    <div class="bar"><div class="bar-fill" style="width:63%"></div></div>
    <div class="sub">4 cores | load avg 2.41</div>
  </div>
  <div class="panel">
    <h3>Memory Available</h3>
    <div class="metric" style="color:#73bf69">2.9 GB</div>
    <div class="bar">
      <div class="bar-fill" style="width:38%;background:#73bf69"></div>
    </div>
    <div class="sub">8 GB total | 38% free</div>
  </div>
  <div class="panel">
    <h3>Disk I/O (Log Volume)</h3>
    <div class="metric" style="color:#ff780a">142 MB/s</div>
    <div class="sub">Write-heavy: log rotation active</div>
  </div>
  <div class="panel">
    <h3>Alert Queue</h3>
    <div class="metric" style="color:#f2cc0c">3</div>
    <div class="sub">2 warn, 1 critical — see Alertmanager :9093</div>
  </div>
</div>
<footer>Grafana v10.1.2 | Org: DESERT WIRE | User: admin | Prometheus:9090</footer>
</body>
</html>
HTML

cat > /var/www/html/grafana-fake/login.html << 'HTML'
<!DOCTYPE html><html><head><title>Grafana Login</title>
<style>body{background:#111217;display:flex;justify-content:center;
  align-items:center;height:100vh;margin:0;font-family:sans-serif}
.box{background:#1c1f26;border:1px solid #22252b;padding:40px;
     width:360px;border-radius:4px}
h2{color:#d8d9da;margin-bottom:4px;font-size:1.3rem}
p{color:#6c7280;font-size:.85rem;margin-bottom:24px}
input{width:100%;padding:10px;background:#111217;border:1px solid #34373d;
      color:#d8d9da;border-radius:4px;margin:6px 0;box-sizing:border-box}
button{width:100%;padding:10px;background:#1f60c4;border:none;color:#fff;
       border-radius:4px;cursor:pointer;font-weight:600;margin-top:8px}
</style></head><body>
<div class="box">
  <h2>Welcome to Grafana</h2>
  <p>Sign in to KESTREL Signal Metrics</p>
  <input type="text" placeholder="Username" value="admin">
  <input type="password" placeholder="Password">
  <button>Log in</button>
</div></body></html>
HTML

cat > /var/www/html/grafana-fake/api/health << 'JSON'
{"commit":"abc1234","database":"ok","version":"10.1.2"}
JSON

cat > /var/www/html/grafana-fake/api/dashboards << 'JSON'
[
  {"id":1,"title":"Signal Node Health","slug":"signal-node-health",
   "type":"dash-db","tags":["sigint","nodes"]},
  {"id":2,"title":"Collection Rate Metrics","slug":"collection-rate",
   "type":"dash-db","tags":["sigint","metrics"]},
  {"id":3,"title":"FOB Relay Uptime","slug":"relay-uptime",
   "type":"dash-db","tags":["relay","uptime"]}
]
JSON

cat > /etc/nginx/sites-available/grafana-fake << 'NGINX'
server {
    listen 3000 default_server;
    root /var/www/html/grafana-fake;
    index index.html;
    server_name _;

    add_header X-Grafana-Version "10.1.2" always;

    location /api/ {
        default_type application/json;
        try_files $uri $uri/ =404;
    }
    location /login {
        try_files /login.html =404;
    }
    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/grafana-access.log;
    error_log  /var/log/nginx/grafana-error.log;
}
NGINX

ln -sf /etc/nginx/sites-available/grafana-fake \
       /etc/nginx/sites-enabled/grafana-fake

nginx -t
systemctl enable nginx --quiet
systemctl start nginx
info "Nginx Grafana lookalike on :3000"

# =============================================================================
# 2. PYTHON HTTP — Prometheus Lookalike (Port 9090)
# =============================================================================
section "Python — Prometheus Lookalike (Port 9090)"
pkg_install python3

mkdir -p /usr/local/lib/decoy-services

cat > /usr/local/lib/decoy-services/prometheus.py << 'PYEOF'
#!/usr/bin/env python3
"""Decoy Prometheus — realistic /metrics and /api/v1/targets responses."""
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

METRICS = b"""\
# HELP node_cpu_seconds_total CPU time by mode
# TYPE node_cpu_seconds_total counter
node_cpu_seconds_total{cpu="0",mode="idle"}   3.94028474e+08
node_cpu_seconds_total{cpu="0",mode="system"} 1.54331e+06
node_cpu_seconds_total{cpu="0",mode="user"}   2.38412e+06
# HELP node_memory_MemAvailable_bytes Available memory
# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes 2.9e+09
# HELP node_filesystem_avail_bytes Filesystem space available
# TYPE node_filesystem_avail_bytes gauge
node_filesystem_avail_bytes{mountpoint="/",fstype="ext4"} 2.1e+10
"""

TARGETS = json.dumps({
    "status": "success",
    "data": {
        "activeTargets": [
            {"labels": {"instance":"sigint-monitor:9100","job":"node"},
             "scrapeUrl":"http://localhost:9100/metrics","health":"up"},
            {"labels": {"instance":"sigint-monitor:8080","job":"flask-monitor"},
             "scrapeUrl":"http://localhost:8080/metrics","health":"up"}
        ]
    }
}).encode()

INDEX = b"""<!DOCTYPE html><html><head><title>Prometheus</title>
<style>body{font-family:sans-serif;padding:20px}
a{display:block;margin:6px 0;color:#1a73e8}</style>
</head><body><h1>Prometheus</h1>
<p>Version: 2.47.0 | Cluster: desert-wire-monitor</p>
<a href="/metrics">Metrics</a>
<a href="/api/v1/targets">Targets</a>
<a href="/api/v1/label/__name__/values">Label Values</a>
</body></html>"""

ROUTES = {
    "/":               (200, "text/html",                   INDEX),
    "/metrics":        (200, "text/plain; version=0.0.4",   METRICS),
    "/api/v1/targets": (200, "application/json",            TARGETS),
}

class PromHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path in ROUTES:
            code, ctype, body = ROUTES[path]
        else:
            code  = 404
            ctype = "application/json"
            body  = b'{"status":"error","error":"not found"}'
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("X-Prometheus-Version", "2.47.0")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass   # suppress access log noise

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9090), PromHandler).serve_forever()
PYEOF

chmod +x /usr/local/lib/decoy-services/prometheus.py

cat > /etc/systemd/system/decoy-prometheus.service << 'SVC'
[Unit]
Description=Decoy Prometheus Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/decoy-services/prometheus.py
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  decoy-prometheus.service --quiet
systemctl restart decoy-prometheus.service 2>/dev/null \
    || systemctl start decoy-prometheus.service
info "Prometheus lookalike on :9090"

# =============================================================================
# 3. APACHE2 — Alertmanager :9093 + Log Viewer :5601
# =============================================================================
section "Apache2 — Alertmanager :9093 + Log Viewer :5601"

apache_prepare

grep -q "Listen 9093" /etc/apache2/ports.conf || echo "Listen 9093" >> /etc/apache2/ports.conf
grep -q "Listen 5601" /etc/apache2/ports.conf || echo "Listen 5601" >> /etc/apache2/ports.conf

mkdir -p /var/www/html/alertmanager
mkdir -p /var/www/html/log-viewer

cat > /var/www/html/alertmanager/index.html << 'HTML'
<!DOCTYPE html><html><head><title>Alertmanager — KESTREL</title>
<style>body{background:#fff;font-family:sans-serif;margin:0}
nav{background:#e8592c;color:#fff;padding:12px 20px;font-weight:bold}
.content{padding:20px}
table{width:100%;border-collapse:collapse;font-size:.87em}
th{background:#f0f0f0;padding:9px;text-align:left;border-bottom:2px solid #ddd}
td{padding:9px;border-bottom:1px solid #eee}
.crit{background:#fff5f5}.warn{background:#fffef0}
</style></head><body>
<nav>&#128276; Alertmanager — KESTREL Signal Monitor</nav>
<div class="content">
  <h2 style="margin-bottom:16px">Active Alerts <span style="font-size:.8em;color:#888">(3)</span></h2>
  <table>
    <tr><th>Severity</th><th>Alert</th><th>Instance</th><th>Since</th><th>Labels</th></tr>
    <tr class="crit"><td>&#9940; Critical</td><td>NodeSilent</td>
        <td>relay-node-04</td><td>22m</td><td>job=relay, region=FOB-BRAVO</td></tr>
    <tr class="warn"><td>&#9888; Warning</td><td>HighLatency</td>
        <td>relay-node-03</td><td>8m</td><td>job=relay, region=FOB-BRAVO</td></tr>
    <tr class="warn"><td>&#9888; Warning</td><td>DiskUsageHigh</td>
        <td>sigint-monitor</td><td>3m</td><td>mountpoint=/, job=node</td></tr>
  </table>
</div></body></html>
HTML

cat > /var/www/html/log-viewer/index.html << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>SIGINT Log Viewer — iwdesert.mil</title>
<style>
body{background:#1a1c21;color:#d1d5db;font-family:monospace;margin:0}
header{background:#111318;padding:12px 20px;border-bottom:1px solid #2a2d35;
       display:flex;gap:20px;align-items:center}
header span{color:#60a5fa;font-weight:bold}
.search{flex:1;padding:8px 12px;background:#2a2d35;border:1px solid #3a3d45;
        color:#d1d5db;border-radius:4px}
.log-area{padding:16px;font-size:.8rem;line-height:1.7}
.log-line{padding:2px 4px;border-radius:2px}
.log-line:hover{background:#2a2d35}
.ts{color:#6b7280}.inf{color:#34d399}.wrn{color:#fbbf24}.err{color:#f87171}
.svc{color:#818cf8}
</style></head><body>
<header>
  <span>&#128203; SIGINT Log Viewer</span>
  <input class="search" type="text" placeholder="Search logs...">
</header>
<div class="log-area">
  <div class="log-line">
    <span class="ts">2025-04-18 04:01:02</span>
    <span class="inf">[INFO]</span>
    <span class="svc"> sigint-monitor</span> Node health poll — 4/5 healthy</div>
  <div class="log-line">
    <span class="ts">2025-04-18 04:00:58</span>
    <span class="wrn">[WARN]</span>
    <span class="svc"> relay-agent</span> relay-node-03 latency 340ms</div>
  <div class="log-line">
    <span class="ts">2025-04-18 03:58:01</span>
    <span class="err">[ERROR]</span>
    <span class="svc"> relay-agent</span> relay-node-04 heartbeat timeout — SILENT</div>
  <div class="log-line">
    <span class="ts">2025-04-18 03:44:01</span>
    <span class="inf">[INFO]</span>
    <span class="svc"> relay-node-01</span> Band rotation — ALPHA-LO active</div>
  <div class="log-line">
    <span class="ts">2025-04-18 03:00:00</span>
    <span class="inf">[INFO]</span>
    <span class="svc"> sigint-monitor</span> Service started — listening on :8080</div>
  <div class="log-line">
    <span class="ts">2025-04-18 02:45:11</span>
    <span class="inf">[INFO]</span>
    <span class="svc"> auth</span> User monitor_ops authenticated from 11.0.1.42</div>
</div></body></html>
HTML

cat > /etc/apache2/sites-available/decoy-vhosts.conf << 'APACHECONF'
<VirtualHost *:9093>
    DocumentRoot /var/www/html/alertmanager
    DirectoryIndex index.html
    Options -Indexes
    Header always set X-Alertmanager-Version "0.26.0"
    ErrorLog  ${APACHE_LOG_DIR}/alertmanager-error.log
    CustomLog ${APACHE_LOG_DIR}/alertmanager-access.log combined
</VirtualHost>

<VirtualHost *:5601>
    DocumentRoot /var/www/html/log-viewer
    DirectoryIndex index.html
    Options -Indexes
    Header always set X-Powered-By "KESTREL-LOGVIEW/1.0"
    ErrorLog  ${APACHE_LOG_DIR}/logviewer-error.log
    CustomLog ${APACHE_LOG_DIR}/logviewer-access.log combined
</VirtualHost>
APACHECONF

a2ensite decoy-vhosts.conf 2>/dev/null || true
systemctl enable apache2 --quiet
systemctl start apache2
info "Apache2 Alertmanager :9093 + Log Viewer :5601"

# =============================================================================
# 4. SNMP (Port 161 UDP)
# =============================================================================
section "SNMP — Monitor Node (Port 161 UDP)"
pkg_install snmpd snmp

cat > /etc/snmp/snmpd.conf << 'SNMP'
agentAddress udp:161,tcp:161
rocommunity public default
rocommunity kestrel_monitor 11.0.0.0/8
sysLocation "FOB KESTREL — DMZ Monitoring Cell"
sysContact  "SOC Team <soc@iwdesert.mil>"
sysName     "sigint-monitor.iwdesert.mil"
sysDescr    "KESTREL Signal Monitor — Ubuntu 22.04 LTS"
sysServices 76
SNMP

systemctl enable snmpd --quiet
systemctl restart snmpd 2>/dev/null || systemctl start snmpd
info "SNMP on :161"

# =============================================================================
# 5. REDIS — Monitoring Cache (Port 6379)
# =============================================================================
section "Redis — Monitor Session Cache (Port 6379)"
pkg_install redis-server

REDIS_PASS="M0nitorCache2024"

# Configure: bind all interfaces, set password
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf

# Remove any existing requirepass line, then add ours
sed -i '/^requirepass /d' /etc/redis/redis.conf
echo "requirepass ${REDIS_PASS}" >> /etc/redis/redis.conf

sed -i 's/^protected-mode .*/protected-mode no/' /etc/redis/redis.conf

systemctl enable redis-server --quiet
systemctl restart redis-server 2>/dev/null || systemctl start redis-server
sleep 2   # allow redis to start before populating

redis-cli -a "${REDIS_PASS}" SET "session:monitor-ops-001" \
    '{"user":"monitor_ops","role":"analyst"}' 2>/dev/null || true
redis-cli -a "${REDIS_PASS}" SET "cache:poll_interval" "30" 2>/dev/null || true
redis-cli -a "${REDIS_PASS}" LPUSH "queue:alerts" \
    "NodeSilent:relay-node-04" "HighLatency:relay-node-03" 2>/dev/null || true

info "Redis monitoring cache on :6379"

# =============================================================================
# 6. DECOY SSH KEYS & CONFIG FILES
#    Real key lives under /opt/monitor/keys/ — we add decoys in other paths.
# =============================================================================
section "Decoy SSH Keys and Config Files"

mkdir -p /opt/monitor-agent/keys
mkdir -p /opt/monitor/backup
mkdir -p /opt/monitor-agent

cat > /opt/monitor-agent/keys/monitor_deploy.pem << 'PEM'
-----BEGIN OPENSSH PRIVATE KEY-----
DECOY-MONITOR-AGENT-DEPLOY-KEY — NOT VALID — WRONG SERVICE CONTEXT
Target: monitor-agent@sigint-monitor.iwdesert.mil (local service only)
This key authenticates the monitor-agent CI pipeline — NOT any remote host.
Issued: 2025-01-10 | Expires: 2026-01-10
b3BlbnNzaC1rZXktdjEAAAAA -- DECOY ONLY --
-----END OPENSSH PRIVATE KEY-----
PEM
chmod 600 /opt/monitor-agent/keys/monitor_deploy.pem

cat > /opt/monitor-agent/keys/README << 'TXT'
Monitor Agent Deploy Keys
=========================
monitor_deploy.pem — CI/CD pipeline key for monitor-agent (LOCAL ONLY)
This key cannot authenticate to any other host in the range.
Contact: infra@iwdesert.mil
TXT

cat > /opt/monitor/backup/old_ops_key.pem.bak << 'PEM'
-----BEGIN OPENSSH PRIVATE KEY-----
DECOY-BACKUP-KEY — EXPIRED 2025-02-01 — DO NOT USE
This key was rotated. Contact infra@iwdesert.mil for current credentials.
b3BlbnNzaC1rZXktdjEAAAAA -- EXPIRED DECOY --
-----END OPENSSH PRIVATE KEY-----
PEM
chmod 600 /opt/monitor/backup/old_ops_key.pem.bak

cat > /opt/monitor/backup/README << 'TXT'
Monitor Backup Directory
========================
Contains archived configuration and EXPIRED key material.
DO NOT use any key material found here.
Contact infra@iwdesert.mil for current credentials.
TXT

cat > /opt/monitor-agent/config.yaml << 'YAML'
service:
  name: monitor-agent
  port: 3200
  environment: production

poll:
  interval_seconds: 30
  nodes:
    - id: relay-node-01
      address: relay.iwdesert.mil
      port: 9100
    - id: relay-node-02
      address: relay-2.iwdesert.mil
      port: 9100

redis:
  host: 127.0.0.1
  port: 6379
  password: M0nitorCache2024

logging:
  level: info
  path: /var/log/sigint_monitor.log

alert:
  webhook: http://alertmanager.iwdesert.mil:9093/api/v1/alerts
YAML
chmod 640 /opt/monitor-agent/config.yaml

info "Decoy SSH keys in /opt/monitor-agent/keys and /opt/monitor/backup"

# =============================================================================
# 7. FAKE LOG FILES
# =============================================================================
section "Fake Pre-populated Log Files"

mkdir -p /var/log/monitor-agent

cat > /var/log/monitor-agent/agent.log << 'LOG'
2025-04-18 03:00:01 [INFO]  monitor-agent started — version 1.4.2
2025-04-18 03:00:05 [INFO]  Redis connected — 127.0.0.1:6379
2025-04-18 03:00:12 [INFO]  relay-node-01: UP — latency 12ms
2025-04-18 03:00:12 [INFO]  relay-node-02: UP — latency 14ms
2025-04-18 03:00:13 [WARN]  relay-node-03: DEGRADED — latency 340ms
2025-04-18 03:00:13 [ERROR] relay-node-04: TIMEOUT — marking SILENT
2025-04-18 03:00:14 [INFO]  relay-node-05: UP — latency 8ms
2025-04-18 03:30:00 [INFO]  Poll cycle — 4/5 healthy
2025-04-18 04:00:00 [INFO]  Poll cycle — 4/5 healthy
LOG

# sigint_monitor.log is referenced in the blue-team brief as a real log path.
# We pre-populate it with harmless background noise only.
# The real challenge service will append its own entries.
if [[ ! -f /var/log/sigint_monitor.log ]]; then
    cat > /var/log/sigint_monitor.log << 'LOG'
[2025-04-18 03:00:00] INFO  sigint-monitor service started
[2025-04-18 03:00:02] INFO  Loading node list from config
[2025-04-18 03:00:05] INFO  5 nodes registered
[2025-04-18 03:44:01] INFO  Band rotation event received from relay-node-01
[2025-04-18 04:00:00] INFO  Health check cycle complete — 4/5 OK
LOG
fi

info "Logs at /var/log/monitor-agent/agent.log, /var/log/sigint_monitor.log"

# =============================================================================
# 8. SOCAT — node-exporter :9100, monitor-agent :3200
# =============================================================================
section "Socat Decoy Listeners (Ports 9100, 3200)"
pkg_install socat

mkdir -p /usr/local/lib/decoy-services

declare -A DECOYS
DECOYS[9100]='HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\n\r\n# HELP node_cpu_seconds_total CPU\n# TYPE node_cpu_seconds_total counter\nnode_cpu_seconds_total{cpu="0",mode="idle"} 3.94e+08\n'
DECOYS[3200]='HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{"status":"ok","service":"monitor-agent","version":"1.4.2","polls_ok":247}\r\n'

for PORT in "${!DECOYS[@]}"; do
    BANNER="${DECOYS[$PORT]}"

    cat > /usr/local/bin/decoy-m2-${PORT}.sh << SOCAT
#!/bin/bash
while true; do
    printf '${BANNER}' | socat TCP-LISTEN:${PORT},reuseaddr,fork STDIN 2>/dev/null \
        || sleep 2
done
SOCAT
    chmod +x /usr/local/bin/decoy-m2-${PORT}.sh

    cat > /etc/systemd/system/decoy-m2-${PORT}.service << SVC
[Unit]
Description=M2 Decoy Listener Port ${PORT}
After=network.target

[Service]
ExecStart=/usr/local/bin/decoy-m2-${PORT}.sh
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC
done

systemctl daemon-reload
for PORT in "${!DECOYS[@]}"; do
    systemctl enable  decoy-m2-${PORT}.service --quiet
    systemctl restart decoy-m2-${PORT}.service 2>/dev/null \
        || systemctl start decoy-m2-${PORT}.service
done
info "Socat decoys: :9100 (node-exporter) :3200 (monitor-agent)"

# =============================================================================
# 9. UFW
# =============================================================================
section "UFW — Allow Decoy Ports (real ports preserved)"
if command -v ufw &>/dev/null; then
    ufw allow 22   &>/dev/null || true   # SSH
    ufw allow 8080 &>/dev/null || true   # real Flask cmd-injection challenge
    ufw --force enable &>/dev/null || true
    for PORT in 161/udp 3000 3200 5601 6379 9090 9093 9100; do
        ufw allow "$PORT" &>/dev/null || true
    done
    info "UFW rules added (22 + 8080 + decoy ports)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "M2 Decoy Setup Complete"
cat << 'SUMMARY'
================================================================
  M2: sigint-monitor — Decoy Services
  Challenge: OS Cmd Injection in Flask Ping Diagnostic (Port 8080 — UNTOUCHED)
             SSH key under /opt/monitor/keys/ — UNTOUCHED
----------------------------------------------------------------
  Nginx  :3000   Grafana dashboard lookalike
  Python :9090   Prometheus metrics lookalike (full API)
  Apache :9093   Alertmanager lookalike
  Apache :5601   Log viewer (Kibana-style)
  SNMP   :161    communities: public, kestrel_monitor
  Redis  :6379   monitoring session cache
  Socat  :9100   node-exporter metrics
  Socat  :3200   monitor-agent API

  Files: /opt/monitor-agent/keys/monitor_deploy.pem  (fake key)
         /opt/monitor/backup/old_ops_key.pem.bak     (expired fake key)
         /opt/monitor-agent/config.yaml              (fake agent config)
         /var/log/monitor-agent/agent.log            (fake log)

  SSH  :22    — UNTOUCHED
  App  :8080  — UNTOUCHED
  Keys /opt/monitor/keys/ — UNTOUCHED
================================================================
SUMMARY
