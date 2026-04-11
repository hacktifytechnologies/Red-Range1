/**
 * DESERT WIRE — SIGINT Comms Relay Dashboard
 * Node.js / Express
 *
 * VULNERABILITY: SSRF in POST /api/uplink/check
 * The satellite uplink checker fetches any URL server-side.
 * Internal DMZ hosts are reachable — attacker hits:
 *   http://<M2-DMZ-IP>:8080/api/internal/status
 * which returns bootstrap credentials for the monitor dashboard.
 */
'use strict';
const express      = require('express');
const morgan       = require('morgan');
const session      = require('express-session');
const bodyParser   = require('body-parser');
const fetch        = require('node-fetch');
const path         = require('path');
const fs           = require('fs');

const app  = express();
const PORT = process.env.PORT || 80;
const LOG  = '/var/log/desertrelay.log';

// ensure log writable
try { fs.accessSync(LOG, fs.constants.W_OK); } catch(e) { /* ignore */ }

app.use(morgan('combined', {
  stream: { write: msg => { try { fs.appendFileSync(LOG, msg); } catch(e){} } }
}));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(session({ secret: 'dsrt_relay_s3cr3t', resave: false, saveUninitialized: true }));
app.use(express.static(path.join(__dirname, 'public')));

// Operator users (login for the dashboard — not the SSRF target)
const OPERATORS = {
  'relay_op1': { pass: 'Relay@Op2024!', name: 'SSgt. Martinez', clearance: 'SECRET' },
  'relay_op2': { pass: 'Uplink#2024!',  name: 'Cpl. Rahman',    clearance: 'SECRET' },
};

// Relay status data (cosmetic)
const RELAY_STATUS = [
  { id:'REL-01', name:'Alpha Relay',   freq:'8.025 GHz', status:'NOMINAL',   uptime:'99.7%', last_sync:'0:04:12 ago' },
  { id:'REL-02', name:'Bravo Relay',   freq:'7.250 GHz', status:'DEGRADED',  uptime:'94.1%', last_sync:'0:12:45 ago' },
  { id:'REL-03', name:'Charlie Relay', freq:'8.450 GHz', status:'NOMINAL',   uptime:'99.9%', last_sync:'0:01:03 ago' },
  { id:'REL-04', name:'Delta Relay',   freq:'9.100 GHz', status:'OFFLINE',   uptime:'0.0%',  last_sync:'4:32:10 ago' },
  { id:'REL-05', name:'Echo Relay',    freq:'7.750 GHz', status:'NOMINAL',   uptime:'98.3%', last_sync:'0:07:28 ago' },
];

// ── Public routes ─────────────────────────────────────────────────────────
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

app.post('/api/auth/login', (req, res) => {
  const { username, password } = req.body;
  const user = OPERATORS[username];
  if (!user || user.pass !== password)
    return res.status(401).json({ error: 'Invalid credentials' });
  req.session.user = username;
  req.session.name = user.name;
  req.session.clearance = user.clearance;
  res.json({ success: true, name: user.name, clearance: user.clearance });
});

app.post('/api/auth/logout', (req, res) => {
  req.session.destroy();
  res.json({ success: true });
});

app.get('/api/relay/status', (req, res) => {
  res.json({ relays: RELAY_STATUS, timestamp: new Date().toISOString() });
});

// ── VULNERABLE ENDPOINT ──────────────────────────────────────────────────────
// POST /api/uplink/check
// Body: { "target_url": "https://external-host.mil/uplink" }
// Purpose: verify if a satellite uplink endpoint is reachable
// Vulnerability: no URL validation — any internal DMZ host is reachable
// Exploit: POST {"target_url": "http://<M2-DMZ-IP>:8080/api/internal/status"}
// Result: M2's bootstrap credential JSON is returned verbatim
// ─────────────────────────────────────────────────────────────────────────────
app.post('/api/uplink/check', async (req, res) => {
  const { target_url } = req.body;
  if (!target_url || typeof target_url !== 'string') {
    return res.status(400).json({ error: 'target_url required' });
  }

  // Weak filter: only blocks obvious localhost — not RFC1918/DMZ addresses
  if (/localhost|127\.0\.0\.1/i.test(target_url)) {
    return res.status(403).json({ error: 'Local addresses not permitted' });
  }

  try {
    const response = await fetch(target_url, {
      timeout: 8000,
      headers: { 'User-Agent': 'DESERT-WIRE/UplinkChecker-v2.1' }
    });
    const contentType = response.headers.get('content-type') || '';
    let body;
    if (contentType.includes('json')) {
      body = await response.json();
    } else {
      const text = await response.text();
      body = { raw_response: text.substring(0, 4096) };
    }
    res.json({
      target_url,
      http_status: response.status,
      latency_ms:  Math.floor(Math.random() * 50) + 10,
      response:    body,
      checked_at:  new Date().toISOString()
    });
  } catch (err) {
    res.status(503).json({
      target_url,
      error:       err.name === 'AbortError' ? 'Connection timeout' : 'Unreachable',
      detail:      err.message,
      checked_at:  new Date().toISOString()
    });
  }
});

app.get('/api/relay/frequencies', (req, res) => {
  res.json({
    band: 'X-Band / C-Band',
    frequencies: RELAY_STATUS.map(r => ({ id: r.id, freq: r.freq, status: r.status }))
  });
});

app.listen(PORT, '0.0.0.0', () =>
  console.log(`[DESERT WIRE] Relay Dashboard listening on :${PORT}`)
);
