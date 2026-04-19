# APT41 - Operation DESERT WIRE

## Intelligence Brief

**Operation:** DESERT WIRE
**Classification:** TOP SECRET // SIGINT // NOFORN
**Issuing Authority:** Joint Cyber Operations Command (JCOC)
**Date:** [EXERCISE DATE]

---

## Situation

APT41 — A suspected state-sponsored threat actor (tracked internally as
Double Dragon) has been observed conducting reconnaissance operations against SIGINT
Forward Operating Base KESTREL. FOB KESTREL operates a tactical communications
relay cluster that aggregates signals from multiple collection assets in theater.

Initial indicators suggest Double Dragon has already compromised the base's external
communications relay portal — the public-facing platform used by allied liaison
officers to submit frequency schedule updates and check uplink status.

---

## Red Team Brief (Double Dragon Operators)

You are operators for Double Dragon. Your mission is to penetrate the full depth
of FOB KESTREL's signals intelligence infrastructure and reach the classified
signal archive containing collection schedules, source identifiers, and intercept
metadata. These documents would allow Double Dragon to expose HUMINT sources and
compromise ongoing collection operations.

**Entry Point:** The COMMS RELAY DASHBOARD is externally accessible.
**Final Objective:** Read the classified intercept log from the Signal Archive.
**ROE:** No destructive actions. No brute force. Follow the intelligence trail.

### Phase 1 — Initial Access: The Relay Breach
The Satellite Uplink Checker feature on the relay dashboard was designed to let
field operators verify external connectivity. A developer left the internal health
check API of the monitoring system reachable via this feature — it was never meant
to be accessible from outside the DMZ. Use it to extract credentials.

### Phase 2 — Pivot: Monitoring System Takeover
With credentials from Phase 1, authenticate to the SIGINT Network Monitor — an
internal platform tracking the health of all collection nodes. The diagnostic tool
was built for rapid troubleshooting by system operators. It passes host input
directly to the OS. Find it and use it to achieve a shell, then extract the SSH
key material stored for gateway maintenance access.

### Phase 3 — Lateral Movement: Gateway Compromise
The signals gateway serves as the pivot point between the DMZ and the classified
private network. Use the SSH key material from Phase 2 to authenticate as the
gateway operations account. Enumerate the system — an overly permissive sudo rule
was left in place after a Node.js diagnostic tool was deployed. Escalate to root.
Retrieve the API authentication token for the signal processing cluster.

### Phase 4 — Deep Access: Signal Processor Exploitation
The signal processing cluster exposes a REST API used by automated collection
pipelines to submit raw signal data for processing. The API accepts binary
serialized payloads for performance reasons — and deserializes them without validation. The API token from Phase 3 unlocks the
processing endpoint. Craft a malicious payload and achieve RCE.
Extract the archive access credentials from the processor configuration.

### Phase 5 — Final Objective: Archive Breach
The classified signal archive is the final target. SSH in as the archivist account
obtained from Phase 4. Discover that the archive server hosts exports for
automated backup jobs. The NFS configuration uses a
client mounting the share as root retains root privileges on the server's filesystem.

---

## Blue Team Brief (FOB KESTREL SOC)

You are the Security Operations Cell at FOB KESTREL. A THREATCON DELTA alert was
issued after anomalous HTTP requests were detected against the external relay portal.
Your mission is to detect, analyze, and document each stage of the attack.

**For each scenario you must:**
- Identify the specific log evidence of the attack
- Name the technique used (MITRE ATT&CK)
- Identify the affected account/service
- Provide the remediation steps

**Key Log Sources:**
- M1: `/var/log/desertrelay.log` (Node.js access log)
- M2: `journalctl -u sigint-monitor`, `/var/log/sigint_monitor.log`
- M3: `/var/log/auth.log` (sudo events, SSH logins)
- M4: `journalctl -u sigint-processor`, pickle deserialization events
- M5: `/var/log/syslog` (NFS mount events), auditd

---

## Chain of Compromise — Summary

```
[Internet / WireGuard VPN]
         │
         ▼ Port 80/443
┌─────────────────────────────┐
│  M1: sigint-relay           │  PHASE 1
│  Comms Relay Dashboard      │  SSRF via Satellite Uplink Checker
│  Node.js Express            │  → leaks M2 creds from internal API
└──────────────┬──────────────┘
               │  monitor_admin : S1GN4L#Mon!tor
               ▼  Port 8080
┌─────────────────────────────┐
│  M2: sigint-monitor         │  PHASE 2
│  SIGINT Network Monitor     │  OS cmd injection in Ping Diagnostic
│  Python Flask               │  → RCE → SSH key for sigops@M3
└──────────────┬──────────────┘
               │  SSH key (sigops_rsa)
               ▼  Port 22
┌─────────────────────────────┐
│  M3: sigint-gateway         │  PHASE 3
│  SSH Pivot Host             │  sudo node → root
│  Dual-homed DMZ + Priv      │  → API token for M4
└──────────────┬──────────────┘
               │  DSRT-SIG-4a7f2c91
               ▼  Port 5000
┌─────────────────────────────┐
│  M4: sigint-processor       │  PHASE 4
│  Signal Processing API      │  Python pickle RCE
│  Python Flask               │  → archivist creds for M5
└──────────────┬──────────────┘
               │  archivist : Arch1v3@D3S3RT
               ▼  Port 22 + NFS
┌─────────────────────────────┐
│  M5: sigint-archive         │  PHASE 5
│  Classified Archive         │  NFS no_root_squash → SUID bash
│  NFS Server                 │  → FINAL FLAG
└─────────────────────────────┘
```
