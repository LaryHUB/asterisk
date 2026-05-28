#!/usr/bin/env bash
# Reads MySQL and generates clients.conf, gws.conf, extensions.conf
set -euo pipefail

# ===== Pre-flight =====
if ! command -v mysql >/dev/null 2>&1; then
  echo "ERR: mysql client not found" >&2; exit 2
fi

: "${MYSQL_HOST:?ERR: MYSQL_HOST not set}"
: "${MYSQL_USER:?ERR: MYSQL_USER not set}"
: "${MYSQL_PASSWORD:?ERR: MYSQL_PASSWORD not set}"
: "${MYSQL_DATABASE:=asterisk}"

CLIENTS=/etc/asterisk/clients.conf
GWS=/etc/asterisk/gws.conf
EXTEN=/etc/asterisk/extensions.conf

MY="mysql -h${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_PASSWORD} -N -B ${MYSQL_DATABASE}"

# ===== Wait for MySQL (max 30s) =====
echo "INFO: waiting for MySQL at ${MYSQL_HOST}..."
for i in $(seq 1 15); do
  if $MY -e "SELECT 1" >/dev/null 2>&1; then
    echo "INFO: MySQL ready"; break
  fi
  [[ $i -eq 15 ]] && { echo "ERR: MySQL not available after 30s" >&2; exit 3; }
  sleep 2
done

# ===== Fetch data =====
CLIENTS_DATA=$($MY -e "SELECT user, password, prefix, gateway FROM sip_clients WHERE active=1 ORDER BY user") \
  || { echo "ERR: sip_clients query failed" >&2; exit 4; }

GATEWAYS_DATA=$($MY -e "SELECT gateway, gateway_pass, client FROM sip_gateways WHERE active=1 ORDER BY gateway") \
  || { echo "ERR: sip_gateways query failed" >&2; exit 4; }

# ===== clients.conf =====
: > "$CLIENTS"
while IFS=$'\t' read -r user password prefix gateway; do
  cat >> "$CLIENTS" <<EOF

[${user}]
type=friend
host=dynamic
username=${user}
secret=${password}
context=${user}
disallow=all
allow=alaw
allow=ulaw
allow=g729
allow=g723
dtmfmode=rfc2833
nat=force_rport,comedia
canreinvite=no
directmedia=no
qualify=yes
EOF
done <<< "$CLIENTS_DATA"

# ===== gws.conf =====
: > "$GWS"
while IFS=$'\t' read -r gateway gateway_pass client; do
  cat >> "$GWS" <<EOF

[${gateway}]
type=friend
host=dynamic
username=${gateway}
secret=${gateway_pass}
context=${gateway}
disallow=all
allow=alaw
allow=ulaw
allow=g729
allow=g723
dtmfmode=rfc2833
nat=force_rport,comedia
canreinvite=no
directmedia=no
qualify=yes
EOF
done <<< "$GATEWAYS_DATA"

# ===== extensions.conf =====
cat > "$EXTEN" <<'EOF'
[general]
static=yes
writeprotect=no
autofallthrough=yes

EOF

while IFS=$'\t' read -r user password prefix gateway; do
  cat >> "$EXTEN" <<EOF
[${user}]
exten => _X.,1,GotoIf(\$["\${EXTEN:0:1}" = "7" & \${LEN(\${EXTEN})}=11]?change:send)
exten => _X.,n(change),Set(CALLED=8\${EXTEN:1})
exten => _X.,n,Dial(SIP/${prefix}\${CALLED}@${gateway})
exten => _X.,n,Hangup()
exten => _X.,n(send),Dial(SIP/${prefix}\${EXTEN}@${gateway})
exten => _X.,n,Hangup()

EOF
done <<< "$CLIENTS_DATA"

while IFS=$'\t' read -r gateway gateway_pass client; do
  cat >> "$EXTEN" <<EOF
[${gateway}]
exten => _[+0-9]X.,1,Dial(SIP/${client})
same => n,Hangup()

EOF
done <<< "$GATEWAYS_DATA"

echo "RESULT: OK — clients=$(grep -c '^\[' "$CLIENTS") gws=$(grep -c '^\[' "$GWS") exten=$(grep -c '^\[' "$EXTEN")"
