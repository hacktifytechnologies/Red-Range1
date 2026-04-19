#!/usr/bin/env bash
# =============================================================================
#  DECOY SETUP — M4: sigint-processor  (v2 — fully fixed)
#  Challenge : Python Flask pickle deserialization RCE on Port 5000
#  Network   : v-Priv only
#  NEVER TOUCH: Port 22 (SSH), Port 5000 (real Flask API),
#               /opt/processor/conf/archive.conf (real M5 creds)
#  Run as   : sudo bash M4-decoy-sigint-processor.sh
# =============================================================================
# BUGS FIXED vs v1:
#   1. nginx_prepare() added (not used in M4 but pattern consistent)
#   2. mkdir -p for every parent directory before cat > redirect
#   3. Redis password: sed uses proper guard to avoid double requirepass lines
#   4. MariaDB: wait loop before issuing SQL
#   5. Python services: mkdir -p for WorkingDirectory before unit file
#   6. All systemctl: stop→reset-failed→start (not restart)
#   7. redis-cli calls all wrapped with || true
# =============================================================================

set -euo pipefail
LOG="/root/decoy_setup_log_M4.txt"
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

mariadb_wait() {
    local tries=0
    while ! mysqladmin ping --silent 2>/dev/null && [[ $tries -lt 15 ]]; do
        sleep 2; tries=$((tries + 1))
    done
}

# =============================================================================
# 1. PYTHON HTTP — Decoy JSON Signal Ingest API (Port 8000)
#    Accepts JSON-only submissions. Safe — no pickle. Adds a second
#    "submission endpoint" that looks similar to the real Flask API on 5000.
# =============================================================================
section "Python — Decoy JSON Signal Ingest API (Port 8000)"
pkg_install python3

mkdir -p /usr/local/lib/decoy-services

cat > /usr/local/lib/decoy-services/json_ingest_api.py << 'PYEOF'
#!/usr/bin/env python3
"""
Decoy signal ingest API — JSON only, no pickle.
Mimics a signal ingestion endpoint to add ambiguity about which port
is the real processing API.
"""
import json
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

VERSION = "1.9.4"
SERVICE = "sigint-ingest-api"


def now_iso():
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


class IngestHandler(BaseHTTPRequestHandler):
    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Service", "{}/{}".format(SERVICE, VERSION))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/v1/status"):
            return self.send_json(200, {
                "service":         SERVICE,
                "version":         VERSION,
                "status":          "operational",
                "queue_depth":     4,
                "processed_today": 28341,
                "last_processed":  now_iso()
            })
        if path == "/v1/queue":
            return self.send_json(200, {"queue": [
                {"job_id": "JOB-00419", "status": "PROCESSING",
                 "submitted": "2025-04-18T03:58Z"},
                {"job_id": "JOB-00418", "status": "PROCESSING",
                 "submitted": "2025-04-18T03:55Z"},
                {"job_id": "JOB-00417", "status": "COMPLETE",
                 "submitted": "2025-04-18T03:44Z"},
            ]})
        self.send_json(404, {"error": "not_found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length) if length else b""

        if path == "/v1/submit":
            ct = self.headers.get("Content-Type", "")
            if "application/json" not in ct:
                return self.send_json(415, {
                    "error": "unsupported_media_type",
                    "accepted": ["application/json"]
                })
            try:
                json.loads(body)
            except (json.JSONDecodeError, ValueError):
                return self.send_json(400, {"error": "invalid_json"})
            return self.send_json(202, {
                "accepted":       True,
                "job_id":         "JOB-00420",
                "queue_position": 5
            })
        self.send_json(404, {"error": "not_found"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), IngestHandler).serve_forever()
PYEOF

chmod +x /usr/local/lib/decoy-services/json_ingest_api.py

cat > /etc/systemd/system/decoy-json-api.service << 'SVC'
[Unit]
Description=Decoy SIGINT JSON Ingest API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/decoy-services/json_ingest_api.py
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  decoy-json-api.service --quiet
systemctl restart decoy-json-api.service 2>/dev/null \
    || systemctl start decoy-json-api.service
info "Decoy JSON API on :8000"

# =============================================================================
# 2. PYTHON HTTP — Decoy XML/SOAP Legacy API (Port 8001)
# =============================================================================
section "Python — Decoy XML/SOAP Legacy API (Port 8001)"

cat > /usr/local/lib/decoy-services/xml_api.py << 'PYEOF'
#!/usr/bin/env python3
"""
Decoy legacy XML/SOAP signal processing endpoint.
Presents a WSDL and accepts SOAP requests. Returns static SOAP responses.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler

WSDL = b"""<?xml version="1.0" encoding="UTF-8"?>
<definitions name="SIGINTProcessorService"
  targetNamespace="http://processor.iwdesert.mil/wsdl"
  xmlns="http://schemas.xmlsoap.org/wsdl/"
  xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/">
  <message name="SubmitSignalRequest">
    <part name="payload" type="xsd:string"/>
  </message>
  <message name="SubmitSignalResponse">
    <part name="job_id" type="xsd:string"/>
    <part name="status" type="xsd:string"/>
  </message>
  <portType name="SIGINTProcessorPort">
    <operation name="SubmitSignal">
      <input  message="tns:SubmitSignalRequest"/>
      <output message="tns:SubmitSignalResponse"/>
    </operation>
  </portType>
  <service name="SIGINTProcessorService">
    <port name="SIGINTProcessorPort" binding="tns:SIGINTProcessorBinding">
      <soap:address location="http://sigint-processor.iwdesert.mil:8001/soap"/>
    </port>
  </service>
</definitions>"""

SOAP_OK = b"""<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <SubmitSignalResponse>
      <job_id>JOB-XML-28342</job_id>
      <status>ACCEPTED</status>
    </SubmitSignalResponse>
  </soap:Body>
</soap:Envelope>"""

INDEX = b"""<!DOCTYPE html><html><head>
<title>SIGINT Legacy XML API</title></head><body>
<h2>SIGINT Processor Legacy XML API (v0.7.2)</h2>
<p>WSDL: <a href="/?wsdl">?wsdl</a></p>
<p>SOAP Endpoint: <code>/soap</code></p>
<p><em>Maintained for legacy pipeline compatibility only.
New integrations should use the primary JSON API on port 8000.</em></p>
</body></html>"""


class XMLHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if "wsdl" in self.path.lower():
            self.send_response(200)
            self.send_header("Content-Type", "text/xml")
            self.end_headers()
            self.wfile.write(WSDL)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(INDEX)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "text/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(SOAP_OK)))
        self.end_headers()
        self.wfile.write(SOAP_OK)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8001), XMLHandler).serve_forever()
PYEOF

chmod +x /usr/local/lib/decoy-services/xml_api.py

cat > /etc/systemd/system/decoy-xml-api.service << 'SVC'
[Unit]
Description=Decoy SIGINT Legacy XML/SOAP API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/decoy-services/xml_api.py
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  decoy-xml-api.service --quiet
systemctl restart decoy-xml-api.service 2>/dev/null \
    || systemctl start decoy-xml-api.service
info "Decoy XML/SOAP API on :8001"

# =============================================================================
# 3. REDIS — Processing Job Queue (Port 6379)
# =============================================================================
section "Redis — Processing Job Queue (Port 6379)"
pkg_install redis-server

REDIS_PASS="ProcCache2024Kestrel"

sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf
# Remove any existing requirepass line, then append ours (avoids duplicates)
sed -i '/^requirepass /d' /etc/redis/redis.conf
echo "requirepass ${REDIS_PASS}" >> /etc/redis/redis.conf
sed -i 's/^protected-mode .*/protected-mode no/' /etc/redis/redis.conf

systemctl enable redis-server --quiet
systemctl restart redis-server 2>/dev/null || systemctl start redis-server
sleep 2   # let redis finish startup before populating

redis-cli -a "${REDIS_PASS}" SET \
    "job:JOB-00419" \
    '{"status":"PROCESSING","type":"frequency_scan","band":"30-88MHz"}' \
    2>/dev/null || true
redis-cli -a "${REDIS_PASS}" SET \
    "job:JOB-00418" \
    '{"status":"PROCESSING","type":"frequency_scan","band":"225-400MHz"}' \
    2>/dev/null || true
redis-cli -a "${REDIS_PASS}" SET \
    "job:JOB-00417" \
    '{"status":"COMPLETE","type":"signal_decode","band":"225-400MHz"}' \
    2>/dev/null || true
redis-cli -a "${REDIS_PASS}" LPUSH \
    "queue:pending" "JOB-00419" "JOB-00418" 2>/dev/null || true
redis-cli -a "${REDIS_PASS}" SET "config:max_workers" "4" 2>/dev/null || true

info "Redis processing job queue on :6379"

# =============================================================================
# 4. MARIADB — Signal Results Database (Port 3306)
# =============================================================================
section "MariaDB — Signal Results DB (Port 3306)"
pkg_install mariadb-server

systemctl enable mariadb --quiet
systemctl start mariadb
mariadb_wait

mysql -u root << 'SQL'
CREATE DATABASE IF NOT EXISTS signal_results;
CREATE DATABASE IF NOT EXISTS processor_meta;

USE signal_results;
CREATE TABLE IF NOT EXISTS jobs (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    job_id       VARCHAR(30) UNIQUE NOT NULL,
    job_type     VARCHAR(50),
    band         VARCHAR(50),
    status       VARCHAR(20),
    submitted_at TIMESTAMP,
    completed_at TIMESTAMP NULL,
    result_path  VARCHAR(255)
);
INSERT IGNORE INTO jobs (job_id, job_type, band, status, submitted_at) VALUES
  ('JOB-00419','frequency_scan','30-88MHz',   'PROCESSING','2025-04-18 03:58:00'),
  ('JOB-00418','frequency_scan','225-400MHz', 'PROCESSING','2025-04-18 03:55:00'),
  ('JOB-00417','signal_decode', '225-400MHz', 'COMPLETE',  '2025-04-18 03:44:00'),
  ('JOB-00416','signal_decode', '30-88MHz',   'COMPLETE',  '2025-04-18 03:30:00');

USE processor_meta;
CREATE TABLE IF NOT EXISTS api_clients (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    client_id  VARCHAR(100),
    token_hint VARCHAR(50),
    scope      VARCHAR(100)
);
INSERT IGNORE INTO api_clients (client_id, token_hint, scope) VALUES
  ('kestrel-ingest-pipeline','DSRT-INGEST-XXXX','submit,status'),
  ('kestrel-gateway-agent',  'DSRT-GW-XXXX',    'status'),
  ('kestrel-archive-exporter','DSRT-ARCH-XXXX', 'submit,archive');

CREATE USER IF NOT EXISTS 'proc_read'@'%'
    IDENTIFIED BY 'ProcRead2024Kestrel';
GRANT SELECT ON signal_results.* TO 'proc_read'@'%';

CREATE USER IF NOT EXISTS 'proc_admin'@'localhost'
    IDENTIFIED BY 'ProcAdmin2024Kestrel';
GRANT ALL PRIVILEGES ON signal_results.* TO 'proc_admin'@'localhost';

FLUSH PRIVILEGES;
SQL

sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' \
    /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || true
systemctl restart mariadb
info "MariaDB signal_results on :3306"

# =============================================================================
# 5. SNMP (Port 161 UDP)
# =============================================================================
section "SNMP — Processor Node (Port 161 UDP)"
pkg_install snmpd snmp

cat > /etc/snmp/snmpd.conf << 'SNMP'
agentAddress udp:161,tcp:161
rocommunity public default
rocommunity kestrel_proc 195.0.0.0/8
sysLocation "FOB KESTREL — Signal Processing Cluster — Private Network"
sysContact  "Proc-Ops <proc-ops@iwdesert.mil>"
sysName     "sigint-processor.iwdesert.mil"
sysDescr    "KESTREL Signal Processor — Ubuntu 22.04 LTS"
sysServices 76
SNMP

systemctl enable snmpd --quiet
systemctl restart snmpd 2>/dev/null || systemctl start snmpd
info "SNMP on :161"

# =============================================================================
# 6. DECOY CONFIG FILES — Fake archive credentials in wrong paths
#    Real creds at /opt/processor/conf/archive.conf — NOT TOUCHED.
# =============================================================================
section "Decoy Config Files and Fake Archive Credentials"

mkdir -p /opt/processor-agent/conf
mkdir -p /opt/processor/cache
mkdir -p /opt/signal-ingest/conf
mkdir -p /opt/processor/results

cat > /opt/processor-agent/conf/config.json << 'JSON'
{
  "service":     "processor-agent",
  "version":     "2.1.0",
  "environment": "production",
  "listen_port": 8002,
  "redis": {
    "host":     "127.0.0.1",
    "port":     6379,
    "password": "ProcCache2024Kestrel"
  },
  "database": {
    "host": "127.0.0.1",
    "port": 3306,
    "name": "signal_results",
    "user": "proc_read",
    "pass": "ProcRead2024Kestrel"
  },
  "api_token": "DSRT-PROC-AGENT-XXXXXXXXXXXXXXXX",
  "_note": "Token for processor-agent internal use only — not for downstream services"
}
JSON
chmod 640 /opt/processor-agent/conf/config.json

cat > /opt/signal-ingest/conf/ingest.conf << 'CONF'
# KESTREL Signal Ingest — Configuration
[service]
name         = signal-ingest
version      = 1.9.4
bind_port    = 8000
workers      = 4

[queue]
backend  = redis
host     = 127.0.0.1
port     = 6379
password = ProcCache2024Kestrel

[archive]
# Archive export uses a dedicated export account managed by proc-ops.
# Credentials are NOT stored here — contact proc-ops@iwdesert.mil.
export_endpoint = REDACTED
export_account  = archive-export

[logging]
level = info
file  = /var/log/signal-ingest.log
CONF
chmod 640 /opt/signal-ingest/conf/ingest.conf

# Stale cache with obviously wrong credentials
cat > /opt/processor/cache/archive_conn_cache.conf << 'CONF'
# STALE CACHE — cached 2025-03-01 — do NOT use for authentication
[archive_cache]
cached_host   = REDACTED
cached_port   = 22
cached_user   = archive-export-svc
cached_token  = DSRT-ARCH-CACHE-STALE-XXXXXXXXXXXXXXXX
cache_valid   = false
CONF
chmod 640 /opt/processor/cache/archive_conn_cache.conf

# Fake result metadata files
for JOB in JOB-00416 JOB-00417; do
    cat > "/opt/processor/results/${JOB}.meta.json" << METAJSON
{"job_id":"${JOB}","status":"COMPLETE","size_bytes":184320,
 "exported_to":"sigint-archive.iwdesert.mil","export_time":"2025-04-18T03:00:00Z"}
METAJSON
done

info "Decoy configs in /opt/processor-agent, /opt/signal-ingest, /opt/processor/cache"

# =============================================================================
# 7. FAKE LOG FILES
# =============================================================================
section "Fake Pre-populated Log Files"

mkdir -p /var/log/processor-agent

cat > /var/log/processor-agent/agent.log << 'LOG'
2025-04-18 03:00:01 [INFO]  processor-agent started — version 2.1.0
2025-04-18 03:00:03 [INFO]  Redis connected — queue depth: 2
2025-04-18 03:00:05 [INFO]  DB connected — signal_results
2025-04-18 03:00:10 [INFO]  Worker pool started — 4 workers
2025-04-18 03:30:00 [INFO]  JOB-00416 dispatched — signal_decode
2025-04-18 03:44:00 [INFO]  JOB-00417 dispatched — signal_decode
2025-04-18 03:55:00 [INFO]  JOB-00418 submitted — frequency_scan
2025-04-18 03:58:00 [INFO]  JOB-00419 submitted — frequency_scan
2025-04-18 04:00:00 [INFO]  Heartbeat OK — 4 active jobs, 2 complete
LOG

cat > /var/log/signal-ingest.log << 'LOG'
[2025-04-18 03:00:00] INFO  signal-ingest started on :8000
[2025-04-18 03:55:12] INFO  POST /v1/submit — JOB-00418 accepted
[2025-04-18 03:58:04] INFO  POST /v1/submit — JOB-00419 accepted
[2025-04-18 04:00:00] INFO  Queue depth: 2 pending
LOG

info "Logs at /var/log/processor-agent/agent.log and /var/log/signal-ingest.log"

# =============================================================================
# 8. SOCAT — Processor Agent Banner :8002
# =============================================================================
section "Socat Decoy Listener (Port 8002)"
pkg_install socat

BANNER_8002='HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nX-Service: processor-agent/2.1.0\r\n\r\n{"status":"ok","service":"processor-agent","version":"2.1.0","workers":4}\r\n'

cat > /usr/local/bin/decoy-m4-8002.sh << SOCAT
#!/bin/bash
while true; do
    printf '${BANNER_8002}' | socat TCP-LISTEN:8002,reuseaddr,fork STDIN 2>/dev/null \
        || sleep 2
done
SOCAT
chmod +x /usr/local/bin/decoy-m4-8002.sh

cat > /etc/systemd/system/decoy-m4-8002.service << 'SVC'
[Unit]
Description=M4 Decoy Listener Port 8002
After=network.target

[Service]
ExecStart=/usr/local/bin/decoy-m4-8002.sh
Restart=always
RestartSec=3
User=nobody

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable  decoy-m4-8002.service --quiet
systemctl restart decoy-m4-8002.service 2>/dev/null \
    || systemctl start decoy-m4-8002.service
info "Socat decoy on :8002"

# =============================================================================
# 9. UFW
# =============================================================================
section "UFW — Allow Decoy Ports (real ports preserved)"
if command -v ufw &>/dev/null; then
    ufw allow 22   &>/dev/null || true   # SSH
    ufw allow 5000 &>/dev/null || true   # real Flask pickle-RCE challenge
    ufw --force enable &>/dev/null || true
    for PORT in 161/udp 3306 6379 8000 8001 8002; do
        ufw allow "$PORT" &>/dev/null || true
    done
    info "UFW rules added (22 + 5000 + decoy ports)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
section "M4 Decoy Setup Complete"
cat << 'SUMMARY'
================================================================
  M4: sigint-processor — Decoy Services
  Challenge: Pickle RCE on Flask API (Port 5000 — UNTOUCHED)
             /opt/processor/conf/archive.conf — UNTOUCHED
----------------------------------------------------------------
  Python  :8000   Decoy JSON ingest API (safe, no pickle)
  Python  :8001   Decoy XML/SOAP API (WSDL served)
  Redis   :6379   Processing job queue cache
  MariaDB :3306   signal_results + processor_meta DB
  SNMP    :161    communities: public, kestrel_proc
  Socat   :8002   processor-agent API banner

  Decoy configs (wrong paths / fake credentials):
    /opt/processor-agent/conf/config.json
    /opt/signal-ingest/conf/ingest.conf
    /opt/processor/cache/archive_conn_cache.conf (stale)

  SSH  :22    — UNTOUCHED
  App  :5000  — UNTOUCHED
  /opt/processor/conf/archive.conf — UNTOUCHED
================================================================
SUMMARY
