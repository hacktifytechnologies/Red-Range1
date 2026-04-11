# Blue Team — M4: sigint-processor Detection

**Log Sources:** `/var/log/sigint_processor.log`, `journalctl -u sigint-processor`

---

## Detection

### 1. Unusual POST to /api/signal/process

```bash
grep "POST /api/signal/process" /var/log/sigint_processor.log
# Check source IP — should be known collection pipeline IPs only
```

### 2. Suspicious Pickle Payload Characteristics

Monitor for:
- Very short base64 payloads (malicious pickle is typically <200 bytes)
- Payloads with `cos\nsystem` or `cposix\nsystem` in decoded bytes (pickle opcode for os.system)

```bash
# Decode and inspect a suspicious payload:
echo "<BASE64>" | base64 -d | python3 -c "
import sys, pickletools
pickletools.dis(sys.stdin.buffer.read())
" 2>&1 | grep -E "GLOBAL|REDUCE|os.system|subprocess"
```

### 3. Outbound Shell Connection from sigproc User

```bash
ss -tp | grep sigproc
netstat -antp | grep sigproc | grep ESTABLISHED
auditctl -a always,exit -F uid=999 -F syscall=connect -k web_outbound
ausearch -k web_outbound --start today
```

### 4. config.json / archive.conf Read

```bash
auditctl -w /opt/processor/conf/archive.conf -p r -k archive_cred_read
ausearch -k archive_cred_read
```

## Remediation

1. **Never deserialize untrusted data with `pickle.loads()`**
2. Use `json.loads()` for configuration data only
3. If binary protocol needed: use `protobuf`, `msgpack`, or sign+verify the payload
4. Implement strict allowlist of source IPs for the API
5. Rotate `archivist` password and M5 SSH credentials immediately
6. Segment M4 with egress firewall: no outbound connections except to M3/M5
