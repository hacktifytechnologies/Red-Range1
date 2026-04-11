# Operation DESERT WIRE — Participant Assessment
## Challenge Verification Questions

> **Instructions:**
> - Each scenario has **3 MCQs** (choose the single best answer) and **2 Static Answer** questions
> - Questions are based on information gathered **during exploitation** — you must have solved the challenge to answer correctly
> - Static Question 1 in each scenario is always the **Flag Submission**
> - Answers are provided at the end of this document for facilitator use only

---

---

# SCENARIO 1 — Ghost Signal (M1: sigint-relay)
### *SSRF via Satellite Uplink Checker*

---

### MCQ 1.1
**After discovering the SSRF vulnerability in the Satellite Uplink Checker, you probe the DMZ subnet. Which API endpoint on the internal monitoring server (M2) leaks bootstrap credentials when accessed via the SSRF?**

- A) `/api/auth/login`
- B) `/api/relay/status`
- C) `/api/internal/status`
- D) `/api/monitor/bootstrap`
- E) `/api/diagnostic/health`

---

### MCQ 1.2
**The SSRF filter on M1 blocks certain addresses. Which of the following target URLs would be BLOCKED by the filter and return a 403 error?**

- A) `http://11.0.0.50:8080/api/internal/status`
- B) `http://172.16.0.1:8080/status`
- C) `http://localhost/api/internal/status`
- D) `http://195.0.0.10:5000/api/status`
- E) `http://10.0.0.1:8080/health`

---

### MCQ 1.3
**When you successfully exploit the SSRF and retrieve the bootstrap credentials from M2's internal API, what is the username returned in the JSON response?**

- A) `sigint_admin`
- B) `relay_operator`
- C) `monitor_op`
- D) `monitor_admin`
- E) `fob_kestrel_admin`

---

### Static Question 1.4 — Flag Submission
**Submit the flag found on M1 after achieving SSRF-based access:**

**Answer:** `FLAG{ssrf_relay_breach_achieved}`

---

### Static Question 1.5
**What is the password returned alongside the username in M2's `/api/internal/status` bootstrap credentials response?**

**Answer:** `S1GN4L#Mon!tor`

---

---

# SCENARIO 2 — Shadow Diagnostic (M2: sigint-monitor)
### *OS Command Injection in Network Diagnostic Tool*

---

### MCQ 2.1
**The command injection vulnerability on M2 exists in which API endpoint?**

- A) `POST /api/nodes/check`
- B) `POST /api/diagnostic/ping`
- C) `POST /api/monitor/execute`
- D) `GET /api/diagnostic/traceroute`
- E) `POST /api/signal/probe`

---

### MCQ 2.2
**After successfully injecting a command via the ping diagnostic, you find an SSH private key stored on M2. What is the full file path of this key?**

- A) `/home/sigmon/.ssh/id_rsa`
- B) `/opt/sigmon/keys/gateway_rsa`
- C) `/opt/monitor/keys/sigops_rsa`
- D) `/etc/ssh/sigops_private_key`
- E) `/var/sigint/keys/gateway.pem`

---

### MCQ 2.3
**The username associated with the SSH private key found on M2 — which user does it authenticate as on M3 (sigint-gateway)?**

- A) `sigmon`
- B) `gateway_ops`
- C) `sigint`
- D) `sigops`
- E) `kestrel_admin`

---

### Static Question 2.4 — Flag Submission
**Submit the flag found inside `/opt/sigmon/classified/flag2.txt` on M2:**

**Answer:** `FLAG{301d2eaf3e3cfd5c_cmd_inject_monitor}`

---

### Static Question 2.5
**What Linux command injection payload (appended after a valid IP with semicolon) would you use to read the flag file? Provide the exact injected portion after the semicolon:**

**Answer:** `cat /opt/sigmon/classified/flag2.txt`

---

---

# SCENARIO 3 — Broken Trust (M3: sigint-gateway)
### *sudo node GTFOBin Privilege Escalation*

---

### MCQ 3.1
**After SSHing into M3 as the `sigops` user and running `sudo -l`, which binary is listed as available with NOPASSWD for all commands?**

- A) `/usr/bin/python3`
- B) `/usr/bin/bash`
- C) `/usr/bin/node`
- D) `/usr/local/bin/node`
- E) `/usr/bin/npm`

---

### MCQ 3.2
**Which of the following commands correctly exploits the sudo misconfiguration on M3 to spawn a root shell using the GTFOBin technique?**

- A) `sudo node --shell /bin/bash`
- B) `sudo node -e 'process.setuid(0); require("child_process").spawn("/bin/bash")'`
- C) `sudo node -e 'require("child_process").spawn("/bin/bash", {stdio: [0,1,2]})'`
- D) `sudo node --exec /bin/bash -i`
- E) `sudo node /bin/bash`

---

### MCQ 3.3
**After escalating to root on M3, you find a configuration file at `/opt/gateway/config.json` containing an API token for the downstream signal processing service. What is the token key name in the JSON structure?**

- A) `api_key`
- B) `bearer_token`
- C) `auth_token`
- D) `access_token`
- E) `service_token`

---

### Static Question 3.4 — Flag Submission
**Submit the flag found at `/root/flag3.txt` on M3:**

**Answer:** `FLAG{sudo_node_pivot_achieved}`

---

### Static Question 3.5
**What is the exact API Bearer token value found in `/opt/gateway/config.json` that authenticates to the M4 Signal Processing API?**

**Answer:** `DSRT-SIG-4a7f2c91`

---

---

# SCENARIO 4 — Poisoned Pipeline (M4: sigint-processor)
### *Python Pickle Deserialization RCE*

---

### MCQ 4.1
**The Signal Processing API on M4 accepts serialized payloads on which endpoint, and what HTTP method does it use?**

- A) `GET /api/signal/deserialize`
- B) `POST /api/signal/process`
- C) `PUT /api/signal/ingest`
- D) `POST /api/signal/execute`
- E) `POST /api/pipeline/submit`

---

### MCQ 4.2
**When crafting a Python Pickle RCE payload, which Python class method must be defined to control what code executes during deserialization?**

- A) `__init__`
- B) `__exec__`
- C) `__call__`
- D) `__reduce__`
- E) `__deserialize__`

---

### MCQ 4.3
**After achieving RCE on M4, you find the M5 archive credentials in a configuration file. What is the full path of that configuration file?**

- A) `/opt/sigproc/conf/credentials.ini`
- B) `/opt/processor/conf/archive.conf`
- C) `/etc/sigint/archive_access.conf`
- D) `/opt/sigproc/classified/archive.json`
- E) `/home/sigproc/config/m5_access.conf`

---

### Static Question 4.4 — Flag Submission
**Submit the flag found at `/opt/sigproc/classified/flag4.txt` on M4:**

**Answer:** `FLAG{pickle_rce_processor_executed}`

---

### Static Question 4.5
**What is the SSH username found in `/opt/processor/conf/archive.conf` that provides access to M5 (sigint-archive)?**

**Answer:** `archivist`

---

---

# SCENARIO 5 — Final Breach (M5: sigint-archive)
### *NFS no_root_squash → SUID Bash Escape*

---

### MCQ 5.1
**You discover M5 is running an NFS server. Which command, run from M4 (where you have root), reveals the NFS exports available on M5?**

- A) `nmap --script nfs-showmount <M5-IP>`
- B) `showmount -e <M5-IP>`
- C) `rpcinfo -p <M5-IP>`
- D) `mount --show <M5-IP>`
- E) `nfsstat -m <M5-IP>`

---

### MCQ 5.2
**The NFS export on M5 is misconfigured with `no_root_squash`. What does this mean in the context of this attack?**

- A) Root on the NFS server has no privileges on the client machine
- B) Any user can mount the share without authentication
- C) A client connecting as root retains root privileges on the server's filesystem
- D) The NFS share is exported read-only to all clients
- E) The root user on the server cannot access the mounted share

---

### MCQ 5.3
**After mounting the NFS share from M4 as root and copying `/bin/bash` to the mount point with the SUID bit set, which command do you run on M5 (as the `archivist` user) to get a root shell?**

- A) `/opt/sigint/classified-archive/.hidden_bash --root`
- B) `/opt/sigint/classified-archive/.hidden_bash -p`
- C) `bash -s /opt/sigint/classified-archive/.hidden_bash`
- D) `sudo /opt/sigint/classified-archive/.hidden_bash`
- E) `/opt/sigint/classified-archive/.hidden_bash --privilege`

---

### Static Question 5.4 — Flag Submission
**Submit the final flag found at `/opt/sigint/classified-archive/CLASSIFIED_FLAG.txt` on M5:**

**Answer:** `FLAG{nfs_squash_archive_pwned}`

---

### Static Question 5.5
**What is the full path of the NFS export on M5 as shown by `showmount -e`?**

**Answer:** `/opt/sigint/classified-archive`

---

---

# FACILITATOR ANSWER KEY
### (Do not distribute to participants)

| Q#   | Question                                        | Answer       |
|------|-------------------------------------------------|--------------|
| 1.1  | M2 internal endpoint leaking credentials        | **C**        |
| 1.2  | URL blocked by SSRF filter                      | **C**        |
| 1.3  | Username in M2 bootstrap response               | **D**        |
| 1.4  | M1 Flag                                         | `FLAG{ssrf_relay_breach_achieved}` |
| 1.5  | M2 bootstrap password                           | `S1GN4L#Mon!tor` |
| 2.1  | Vulnerable endpoint on M2                       | **B**        |
| 2.2  | SSH private key path on M2                      | **C**        |
| 2.3  | SSH username for M3                             | **D**        |
| 2.4  | M2 Flag                                         | `FLAG{301d2eaf3e3cfd5c_cmd_inject_monitor}` |
| 2.5  | Command injection payload after semicolon       | `cat /opt/sigmon/classified/flag2.txt` |
| 3.1  | Binary available via sudo NOPASSWD on M3        | **C**        |
| 3.2  | Correct GTFOBin command for node                | **C**        |
| 3.3  | API token key name in config.json               | **C**        |
| 3.4  | M3 Flag                                         | `FLAG{sudo_node_pivot_achieved}` |
| 3.5  | Bearer token for M4 API                         | `DSRT-SIG-4a7f2c91` |
| 4.1  | M4 vulnerable endpoint and HTTP method          | **B**        |
| 4.2  | Python method for pickle RCE                    | **D**        |
| 4.3  | Path of M5 credential config on M4              | **B**        |
| 4.4  | M4 Flag                                         | `FLAG{pickle_rce_processor_executed}` |
| 4.5  | SSH username for M5 from archive.conf           | `archivist`  |
| 5.1  | Command to list NFS exports                     | **B**        |
| 5.2  | Meaning of no_root_squash                       | **C**        |
| 5.3  | Command to get root shell via SUID bash         | **B**        |
| 5.4  | M5 Final Flag                                   | `FLAG{nfs_squash_archive_pwned}` |
| 5.5  | NFS export path on M5                           | `/opt/sigint/classified-archive` |

---

## Scoring Guide

| Score   | Percentage | Assessment        |
|---------|------------|-------------------|
| 25/25   | 100%       | Full Chain Compromised — DOMAIN BREACH |
| 20–24   | 80–96%     | Deep Penetration — Minor gaps          |
| 15–19   | 60–76%     | Partial Compromise — Training recommended |
| 10–14   | 40–56%     | Limited Access — Significant gaps      |
| < 10    | < 40%      | Insufficient — Remedial training required |

> **Note:** A participant who submits all 5 correct flags but cannot answer the knowledge questions likely used hints or shared answers. Flag + knowledge answers together indicate genuine exploitation.
