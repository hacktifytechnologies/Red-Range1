# Blue Team — M3: sigint-gateway Detection

**Log Sources:** `/var/log/auth.log`

---

## Detection

### 1. SSH Login with Key (Unusual Source)

```bash
grep "Accepted publickey" /var/log/auth.log | grep sigops
# Source IP should match M2's DMZ IP — if from attacker machine = compromise
```

### 2. Sudo node Invocation

```bash
grep "COMMAND.*node" /var/log/auth.log
grep "sigops.*sudo" /var/log/auth.log
```

IOC: `sigops` running `sudo node` with arguments that spawn `/bin/bash`

### 3. Root Shell from node Process (auditd)

```bash
auditctl -a always,exit -F uid=0 -F syscall=execve -k root_exec
ausearch -k root_exec --start today | grep -v cron
# bash spawned as child of node, euid=0 = escalation
```

### 4. config.json Read

```bash
auditctl -w /opt/gateway/config.json -p r -k config_read
ausearch -k config_read
# Any read of this file outside automated tasks is suspicious
```

## Remediation

- Remove `NOPASSWD: /usr/bin/node` from sudoers immediately
- `rm /etc/sudoers.d/desert-wire-gateway`
- Audit all sudo rules: `sudo -l -U sigops`
- Rotate the M4 API token immediately
- Use a configuration management system (Ansible/Puppet) to enforce sudoers policy
