# GitHub Push Instructions

## Initial Push

```bash
# 1. Extract the ZIP
unzip operation-desert-wire.zip
cd operation-desert-wire

# 2. Initialize git repo
git init
git add .
git commit -m "feat: Operation DESERT WIRE — Initial release

5-machine military SIGINT range
- M1: SSRF (Node.js comms relay)
- M2: OS Command Injection (Flask monitor)
- M3: sudo node GTFOBin (SSH gateway)
- M4: Python Pickle RCE (signal processor)
- M5: NFS no_root_squash (classified archive)

Platform: Ubuntu 22.04, OpenStack
Networks: v-Pub/v-DMZ/v-Priv"

# 3. Create and push to GitHub
git remote add origin https://github.com/<your-org>/operation-desert-wire.git
git branch -M main
git push -u origin main
```

## Recommended .gitignore

```bash
cat > .gitignore << 'EOF'
*.pyc
__pycache__/
node_modules/
*.log
*.pem
*.key
.env
venv/
EOF
git add .gitignore
git commit -m "chore: add .gitignore"
git push
```

## Per-Team Provisioning Notes

Since each snapshot generates unique flags via `openssl rand`:
- Run each `setup.sh` on freshly provisioned VMs (not from snapshot)
- OR modify TTPs to accept a `TEAM_ID` env var and generate deterministic flags:
  `FLAG="FLAG{TEAM${TEAM_ID}_$(echo $TEAM_ID | sha256sum | head -c 12)_ssrf}"`
- Collect flags from `/root/ctf_setup_log.txt` on each VM after setup

## Recommended Directory Layout on GitHub

```
operation-desert-wire/
├── README.md
├── STORYLINE.md
├── NETWORK_DIAGRAM.md
├── GITHUB_PUSH.md
├── machines/
│   ├── M1-sigint-relay/
│   │   ├── setup.sh
│   │   ├── app/
│   │   │   ├── package.json
│   │   │   ├── server.js
│   │   │   └── public/
│   │   ├── solve_red.md
│   │   └── solve_blue.md
│   ├── M2-sigint-monitor/
│   ├── M3-sigint-gateway/
│   ├── M4-sigint-processor/
│   └── M5-sigint-archive/
└── ttps/
    ├── red_01_ssrf_relay_setup.yml
    ├── red_02_monitor_cmdinject_setup.yml
    ├── red_03_gateway_sudo_setup.yml
    ├── red_04_processor_pickle_setup.yml
    └── red_05_archive_nfs_setup.yml
```
