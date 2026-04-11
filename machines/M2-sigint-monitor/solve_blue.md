# Blue Team — M2: sigint-monitor Detection

**Vulnerability:** OS Command Injection
**Log:** `/var/log/sigint_monitor.log`, `journalctl -u sigint-monitor`

---

## Detection

### 1. Command Injection Patterns in POST Body

```bash
# Morgan logs include URL but not body — add body logging or deploy WAF
# Check for shell metacharacters in access log URL patterns:
grep "diagnostic/ping" /var/log/sigint_monitor.log | grep -E "POST" | tail -30

# If body logging enabled:
grep -E ";\s*(id|whoami|cat|bash|nc|curl|wget)" /var/log/sigint_monitor.log
```

### 2. Process Spawned by Gunicorn Worker

```bash
# auditd: bash/sh spawned as child of python/gunicorn
auditctl -a always,exit -F uid=999 -F syscall=execve -k web_exec
ausearch -k web_exec --start today | grep -v gunicorn

# ps at time of attack:
# python3 → sh → bash → cat/nc etc.
```

### 3. SSH Key File Access

```bash
ausearch --start today -f /opt/monitor/keys/sigops_rsa
# A read of the private key file = credential theft
```

### 4. Outbound Reverse Shell

```bash
# Outbound connection from sigmon user
ss -tp | grep sigmon
journalctl -u sigint-monitor | grep "bash -i"
```

## Remediation

1. Validate `host` with strict regex: `^[a-zA-Z0-9.\-]{1,253}$`
2. Use `subprocess.run(["ping","-c","3",host], shell=False)` — NEVER `shell=True` with user input
3. Move SSH keys out of web-accessible paths
4. Run the service with network egress restrictions (no outbound to non-DMZ)
5. Disable the credential bootstrap endpoint `/api/internal/status`
