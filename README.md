# Operation DESERT WIRE — SIGINT Cyber Range

**Classification:** UNCLASSIFIED // EXERCISE ONLY
**Domain Theme:** Military Signals Intelligence Forward Operating Base
**Network:** iwdesert.mil (simulated)
**Platform:** Ubuntu 22.04 Jammy — OpenStack

---

## Machine Summary

| # | Hostname            | Network(s)          | Vulnerability                        | MITRE         |
|---|---------------------|---------------------|--------------------------------------|---------------|
| 1 | sigint-relay        | v-Pub + v-DMZ       | SSRF → internal credential leak      | T1090.002     |
| 2 | sigint-monitor      | v-DMZ               | OS Command Injection (authenticated)  | T1059.004     |
| 3 | sigint-gateway      | v-DMZ + v-Priv      | Sudo node GTFOBin (T1548.003)         | T1548.003     |
| 4 | sigint-processor    | v-Priv              | Python Pickle Deserialization RCE     | T1059.006     |
| 5 | sigint-archive      | v-Priv              | NFS no_root_squash → SUID escape      | T1548.001     |

---

## Credential Chain

```
M1 SSRF  →  /api/internal/status on M2  →  monitor_admin : S1GN4L#Mon!tor
M2 RCE   →  /opt/monitor/keys/sigops_rsa  →  SSH key for sigops@M3
M3 root  →  /opt/gateway/config.json      →  API token for M4 : DSRT-SIG-4a7f2c91
M4 RCE   →  /opt/processor/conf/archive.conf  →  archivist : Arch1v3@D3S3RT
M5 NFS   →  no_root_squash → SUID bash   →  FINAL FLAG
```

---

## Setup Order (per VM)

```bash
sudo bash machines/M1-sigint-relay/setup.sh
sudo bash machines/M2-sigint-monitor/setup.sh
sudo bash machines/M3-sigint-gateway/setup.sh
sudo bash machines/M4-sigint-processor/setup.sh
sudo bash machines/M5-sigint-archive/setup.sh
# Flags logged to /root/ctf_setup_log.txt on each VM
```

---

## OpenStack Network Assignment

| Machine          | Networks                        |
|------------------|---------------------------------|
| sigint-relay     | v-Pub-subnet + v-DMZ-subnet     |
| sigint-monitor   | v-DMZ-subnet                    |
| sigint-gateway   | v-DMZ-subnet + v-Priv-subnet    |
| sigint-processor | v-Priv-subnet                   |
| sigint-archive   | v-Priv-subnet                   |

---

## GitHub Push

```bash
git init operation-desert-wire
cd operation-desert-wire
cp -r /path/to/extracted/* .
git add .
git commit -m "Operation DESERT WIRE — Initial Release"
git remote add origin https://github.com/<your-org>/operation-desert-wire.git
git branch -M main
git push -u origin main
```
