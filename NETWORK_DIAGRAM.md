# Network Diagram — Operation DESERT WIRE

```
         [Operator — WireGuard VPN]
                    │
         [Floating IP 172.24.4.0/24]
                    │ (assigned to M1 only)
                    │
     ┌──────────────▼─────────────────────┐
     │   v-Pub-subnet  203.0.0.0/8        │
     │                                    │
     │  ┌──────────────────────────────┐  │
     │  │  M1: sigint-relay            │  │
     │  │  Node.js Relay Dashboard     │  │
     │  │  Port 80 — SSRF Vulnerable   │  │
     │  │  [Pub NIC + DMZ NIC]         │  │
     │  └──────────────┬───────────────┘  │
     └─────────────────┼──────────────────┘
                       │
     ┌─────────────────▼──────────────────┐
     │   v-DMZ-subnet  11.0.0.0/8         │
     │                                    │
     │  ┌──────────────────────────────┐  │
     │  │  M2: sigint-monitor          │  │
     │  │  Flask Monitor Dashboard     │  │
     │  │  Port 8080 — Cmd Injection   │  │
     │  └──────────────────────────────┘  │
     │                                    │
     │  ┌──────────────────────────────┐  │
     │  │  M3: sigint-gateway          │  │
     │  │  SSH Port 22                 │  │
     │  │  sudo node misconfig         │  │
     │  │  [DMZ NIC + Priv NIC]        │  │
     │  └──────────────┬───────────────┘  │
     └─────────────────┼──────────────────┘
                       │
     ┌─────────────────▼──────────────────┐
     │   v-Priv-subnet  195.0.0.0/8       │
     │                                    │
     │  ┌──────────────────────────────┐  │
     │  │  M4: sigint-processor        │  │
     │  │  Flask API Port 5000         │  │
     │  │  Pickle Deserialization RCE  │  │
     │  └──────────────────────────────┘  │
     │                                    │
     │  ┌──────────────────────────────┐  │
     │  │  M5: sigint-archive          │  │
     │  │  SSH Port 22 + NFS Port 2049 │  │
     │  │  no_root_squash              │  │
     │  └──────────────────────────────┘  │
     └────────────────────────────────────┘
```

## Discovery (No Static IPs)

- **Entry:** Floating IP → M1 port 80
- **M1→M2:** SSRF response reveals M2 DMZ IP and port 8080. Scan: `nmap -p 8080 11.0.0.0/8`
- **M2→M3:** SSH key found in `/opt/monitor/keys/sigops_rsa`. Scan DMZ for port 22.
- **M3→M4:** API token in `/opt/gateway/config.json`. After root on M3, scan private subnet: `nmap -p 5000 195.0.0.0/8`
- **M4→M5:** Credentials in `/opt/processor/conf/archive.conf`. Scan: `nmap -p 22,2049 195.0.0.0/8`
