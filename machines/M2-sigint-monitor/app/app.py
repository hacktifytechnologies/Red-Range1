# DESERT WIRE — SIGINT Network Monitor
# VULNERABILITY: OS Command Injection in POST /api/diagnostic/ping
# The host parameter is passed unsanitized to subprocess.run via shell=True
# Bypass: "8.8.8.8; id" or "8.8.8.8 && cat /opt/sigmon/classified/flag2.txt"

from flask import Flask, render_template, request, session, redirect, url_for, jsonify
import subprocess, os, json, re, time

app = Flask(__name__)
app.secret_key = 'dsrt_sigmon_s3cr3t_k3y_2024_fobkestrel'

USERS = {
    "monitor_admin": {"pass": "S1GN4L#Mon!tor", "name": "SFC Chen", "role": "admin"},
    "monitor_op":    {"pass": "M0nit0r@2024",   "name": "SGT Williams", "role": "operator"},
}

NODES = [
    {"id":"COL-A1","name":"Alpha Collection Array", "type":"ELINT", "status":"ACTIVE",   "signal_db":"-78.4","last_hit":"0:02:11"},
    {"id":"COL-B2","name":"Bravo Direction Finder",  "type":"COMINT","status":"ACTIVE",   "signal_db":"-82.1","last_hit":"0:00:44"},
    {"id":"COL-C3","name":"Charlie SIGINT Node",     "type":"MASINT","status":"DEGRADED", "signal_db":"-94.7","last_hit":"0:15:02"},
    {"id":"COL-D4","name":"Delta Intercept Relay",   "type":"ELINT", "status":"ACTIVE",   "signal_db":"-71.2","last_hit":"0:01:33"},
    {"id":"COL-E5","name":"Echo Collection Point",   "type":"COMINT","status":"OFFLINE",  "signal_db":"N/A",  "last_hit":"6:42:01"},
    {"id":"COL-F6","name":"Foxtrot Direction Array",  "type":"ELINT", "status":"ACTIVE",   "signal_db":"-80.9","last_hit":"0:03:55"},
]

# Exposed to any DMZ host — SSRF target from M1
@app.route("/api/internal/status")
def internal_status():
    return jsonify({
        "service": "SIGINT Network Monitor",
        "version": "3.2.1",
        "environment": "DMZ-PRODUCTION",
        "bootstrap_credentials": {
            "username": "monitor_admin",
            "password": "S1GN4L#Mon!tor",
            "note": "Rotate after DR exercise — IT ticket #4821 pending"
        },
        "node_count": len(NODES),
        "timestamp": time.time()
    })

@app.route("/")
def index():
    if "user" not in session:
        return redirect(url_for("login"))
    return redirect(url_for("dashboard"))

@app.route("/login", methods=["GET","POST"])
def login():
    error = None
    if request.method == "POST":
        u = request.form.get("username","")
        p = request.form.get("password","")
        user = USERS.get(u)
        if user and user["pass"] == p:
            session["user"] = u
            session["name"] = user["name"]
            session["role"] = user["role"]
            return redirect(url_for("dashboard"))
        error = "AUTHENTICATION FAILED — Invalid credentials"
    return render_template("login.html", error=error)

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/dashboard")
def dashboard():
    if "user" not in session:
        return redirect(url_for("login"))
    return render_template("dashboard.html",
        nodes=NODES, user=session["name"], role=session["role"])

@app.route("/api/nodes")
def api_nodes():
    if "user" not in session:
        return jsonify({"error":"Unauthorized"}), 401
    return jsonify({"nodes": NODES})

# ── VULNERABLE ENDPOINT ──────────────────────────────────────────────────────
# POST /api/diagnostic/ping
# Body: {"host": "10.0.0.1"}
# The host value is passed directly to shell=True subprocess — no sanitisation.
# Exploit: {"host": "8.8.8.8; cat /opt/sigmon/classified/flag2.txt"}
# Also:    {"host": "8.8.8.8; cat /opt/monitor/keys/sigops_rsa"}
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/api/diagnostic/ping", methods=["POST"])
def diag_ping():
    if "user" not in session:
        return jsonify({"error":"Unauthorized"}), 401
    data = request.get_json() or {}
    host = data.get("host","")
    if not host:
        return jsonify({"error":"host required"}), 400
    try:
        # VULNERABILITY: shell=True with unsanitized user input
        cmd = f"ping -c 3 -W 2 {host}"
        result = subprocess.run(
            cmd, shell=True, capture_output=True,
            text=True, timeout=15
        )
        return jsonify({
            "host":    host,
            "command": cmd,
            "stdout":  result.stdout,
            "stderr":  result.stderr,
            "rc":      result.returncode
        })
    except subprocess.TimeoutExpired:
        return jsonify({"host": host, "error": "Timeout"})
    except Exception as e:
        return jsonify({"host": host, "error": str(e)})

@app.route("/api/diagnostic/traceroute", methods=["POST"])
def diag_trace():
    if "user" not in session:
        return jsonify({"error":"Unauthorized"}), 401
    data = request.get_json() or {}
    host = data.get("host","")
    if not host or not re.match(r"^[a-zA-Z0-9.\-]+$", host):
        return jsonify({"error":"Invalid host"}), 400
    try:
        result = subprocess.run(
            ["traceroute", "-n", "-m", "10", host],
            capture_output=True, text=True, timeout=20
        )
        return jsonify({"host":host,"output":result.stdout+result.stderr})
    except Exception as e:
        return jsonify({"error":str(e)})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
