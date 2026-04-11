# Blue Team — M5: sigint-archive Detection

**Vulnerability:** NFS no_root_squash
**Log Sources:** `/var/log/syslog` (NFS), auditd, `/var/log/auth.log`

---

## Detection

### 1. NFS Mount from Unexpected Source

```bash
# Monitor NFS connections
grep "nfsd\|mountd" /var/log/syslog | tail -30

# showmount shows who has the share mounted:
showmount -a

# Expected: only known backup servers should mount this share
# Unexpected: M4's private IP (195.x.x.x) mounting the archive
```

### 2. SUID Binary Created in NFS Export

```bash
# Watch for new SUID files in the export directory
find /opt/sigint/classified-archive -perm /4000 2>/dev/null
# A .hidden_bash or any SUID binary appearing here = active exploitation

# auditd watch:
auditctl -w /opt/sigint/classified-archive -p w -k nfs_write
ausearch -k nfs_write | grep -v backup_agent
```

### 3. Root File Read by archivist

```bash
# If attacker ran SUID bash on M5:
auditctl -w /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt -p r -k flag_read
ausearch -k flag_read

# auth.log — archivist login from M4's IP
grep "archivist" /var/log/auth.log | grep "Accepted"
# Source should be known admin workstation, not M4's private IP
```

### 4. Unexpected Process as Root Spawned from archivist Session

```bash
auditctl -a always,exit -F uid=0 -F syscall=execve -k root_spawn
ausearch -k root_spawn --start today
# bash with euid=0 spawned under archivist login session = SUID abuse
```

---

## Remediation

1. **Fix the NFS export immediately:**
   ```bash
   # Change /etc/exports to use root_squash (the default):
   /opt/sigint/classified-archive *(ro,sync,no_subtree_check,root_squash)
   exportfs -ra
   ```
2. Restrict NFS to specific backup server IPs, not `*`:
   `192.168.1.100(ro,sync,root_squash)`
3. Rotate `archivist` password
4. Move the NFS server behind the private subnet firewall
5. Remove any SUID binaries placed in the export:
   `find /opt/sigint -perm /4000 -delete`
6. Use NFSv4 with Kerberos authentication for sensitive exports

---

## Kill Chain Remediation Summary

| Stage | Fix |
|-------|-----|
| M1 SSRF | Allowlist target URLs; remove internal status endpoint |
| M2 Cmd Inject | Use `shell=False`; validate host with regex |
| M3 Sudo node | Remove NOPASSWD sudo rule; use dedicated script |
| M4 Pickle RCE | Replace `pickle` with `json`; validate source IPs |
| M5 NFS squash | Add `root_squash`; restrict to specific client IPs |
