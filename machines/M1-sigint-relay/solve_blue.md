# Blue Team — M1: sigint-relay Detection

**Vulnerability:** SSRF
**Log:** `/var/log/desertrelay.log`

---

## Detection

### 1. SSRF Probe Patterns

```bash
# Internal IPs in POST body to /api/uplink/check
grep "uplink/check" /var/log/desertrelay.log | grep -E "11\.|10\.|192\.168\.|172\."

# Multiple requests to sequential IPs = subnet scan via SSRF
grep "uplink/check" /var/log/desertrelay.log | grep "11\.0\.0\." | wc -l
```

### 2. Internal API Credential Endpoint Hit

```bash
# Hit on /api/internal/status originated from M1's server (not directly from outside)
# Check M2 logs for requests from M1's DMZ IP:
grep "internal/status" /var/log/sigint_monitor.log | grep "$(hostname -I | awk '{print $2}')"
```

### 3. Timeline: Scan → Credential Leak → Monitor Login

Build timeline:
1. Multiple 503/504 responses to `POST /api/uplink/check` (scanning)
2. One 200 response with internal IP as target
3. Subsequent login to M2 from same source IP within minutes

## Remediation

1. Validate `target_url` against an allowlist of approved SATCOM hosts
2. Block all RFC1918 ranges (10.x, 192.168.x, 11.x) in URL validation
3. Move `/api/internal/status` behind authentication or localhost-only binding
4. Use separate service user without DMZ routing access for the check function
