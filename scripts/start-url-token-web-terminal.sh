#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="${1:-ssh-handoff}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-48080}"
CLIENT_IP="${CLIENT_IP:-}"
TTL_MINUTES="${TTL_MINUTES:-30}"
BIND_SCOPE="${BIND_SCOPE:-local}"
UPSTREAM_HOST="127.0.0.1"
UPSTREAM_PORT="${UPSTREAM_PORT:-48081}"
COOKIE_SECURE="${COOKIE_SECURE:-}"
EXPECTED_HOST="${EXPECTED_HOST:-${HOST}:${PORT}}"
EXPECTED_ORIGIN="${EXPECTED_ORIGIN:-}"
FORBID_REUSE_IF_AUTHENTICATED="${FORBID_REUSE_IF_AUTHENTICATED:-0}"
AUTH_GUARD_REGEX="${AUTH_GUARD_REGEX:-(^|[^[:alnum:]_])(Last login:|[@][A-Za-z0-9._-]+:|Welcome to|Linux [A-Za-z0-9._-]+|[#$] $)}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

need tmux
need ttyd
need python3
need node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux new-session -d -s "$SESSION_NAME"
fi

if [[ "$FORBID_REUSE_IF_AUTHENTICATED" == "1" || "$FORBID_REUSE_IF_AUTHENTICATED" =~ ^([Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])$ ]]; then
  PANE_SNAPSHOT="$(tmux capture-pane -t "$SESSION_NAME" -p -S -200 2>/dev/null || true)"
  if printf '%s\n' "$PANE_SNAPSHOT" | grep -Eiq "$AUTH_GUARD_REGEX"; then
    echo "Refusing to launch: tmux session appears already authenticated. Set FORBID_REUSE_IF_AUTHENTICATED=0 to override." >&2
    exit 1
  fi
fi

if ss -ltn | awk '{print $4}' | grep -qE "(^|:)$UPSTREAM_PORT$"; then
  echo "Upstream port already in use: $UPSTREAM_PORT" >&2
  exit 1
fi

if ss -ltn | awk '{print $4}' | grep -qE "(^|:)$PORT$"; then
  echo "Proxy port already in use: $PORT" >&2
  exit 1
fi

ACCESS_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"

SESSION_SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"

EXPIRES_AT="$(TTL_FOR_PY="$TTL_MINUTES" python3 - <<'PY'
import os
from datetime import datetime, timedelta, timezone
minutes = int(os.environ['TTL_FOR_PY'])
print((datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat())
PY
)"

RUNTIME_DIR="$(mktemp -d -t ssh-handoff-${SESSION_NAME}-XXXXXX)"
PROXY_INFO_FILE="$RUNTIME_DIR/proxy-info.json"
PROXY_LOG_FILE="$RUNTIME_DIR/proxy.log"
TTYD_LOG_FILE="$RUNTIME_DIR/ttyd.log"
CLEANUP_SCRIPT="$RUNTIME_DIR/cleanup.sh"
METADATA_FILE="$RUNTIME_DIR/meta.env"
: > "$PROXY_INFO_FILE"

if [[ -z "$EXPECTED_ORIGIN" ]]; then
  if [[ -n "$COOKIE_SECURE" && "$COOKIE_SECURE" != "0" ]]; then
    EXPECTED_ORIGIN="https://$EXPECTED_HOST"
  else
    EXPECTED_ORIGIN="http://$EXPECTED_HOST"
  fi
fi

cat > "$CLEANUP_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TTYD_PID="${TTYD_PID:-}"
PROXY_PID="${PROXY_PID:-}"
RUNTIME_DIR="${RUNTIME_DIR:-}"
if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
  kill "$PROXY_PID" 2>/dev/null || true
fi
if [[ -n "$TTYD_PID" ]] && kill -0 "$TTYD_PID" 2>/dev/null; then
  kill "$TTYD_PID" 2>/dev/null || true
fi
sleep 0.2
if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
  kill -9 "$PROXY_PID" 2>/dev/null || true
fi
if [[ -n "$TTYD_PID" ]] && kill -0 "$TTYD_PID" 2>/dev/null; then
  kill -9 "$TTYD_PID" 2>/dev/null || true
fi
if [[ -n "$RUNTIME_DIR" ]] && [[ -d "$RUNTIME_DIR" ]]; then
  rm -rf "$RUNTIME_DIR"
fi
EOF
chmod 700 "$CLEANUP_SCRIPT"

nohup ttyd -W -i "$UPSTREAM_HOST" -p "$UPSTREAM_PORT" tmux attach -t "$SESSION_NAME" >"$TTYD_LOG_FILE" 2>&1 &
TTYD_PID=$!

nohup env \
  LISTEN_HOST="$HOST" \
  LISTEN_PORT="$PORT" \
  UPSTREAM_HOST="$UPSTREAM_HOST" \
  UPSTREAM_PORT="$UPSTREAM_PORT" \
  ACCESS_TOKEN="$ACCESS_TOKEN" \
  SESSION_SECRET="$SESSION_SECRET" \
  TTL_MS="$((TTL_MINUTES * 60 * 1000))" \
  COOKIE_SECURE="$COOKIE_SECURE" \
  EXPECTED_HOST="$EXPECTED_HOST" \
  EXPECTED_ORIGIN="$EXPECTED_ORIGIN" \
  ALLOWED_CLIENT_IP="$CLIENT_IP" \
  node "$SCRIPT_DIR/url-token-proxy.js" >"$PROXY_INFO_FILE" 2>"$PROXY_LOG_FILE" &
PROXY_PID=$!

cat > "$METADATA_FILE" <<EOF
RUNTIME_DIR=$RUNTIME_DIR
TTYD_PID=$TTYD_PID
PROXY_PID=$PROXY_PID
SESSION_NAME=$SESSION_NAME
HOST=$HOST
PORT=$PORT
UPSTREAM_PORT=$UPSTREAM_PORT
CLIENT_IP=$CLIENT_IP
EXPECTED_HOST=$EXPECTED_HOST
EXPECTED_ORIGIN=$EXPECTED_ORIGIN
EXPIRES_AT=$EXPIRES_AT
EOF

for _ in $(seq 1 50); do
  if [[ -s "$PROXY_INFO_FILE" ]]; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$PROXY_INFO_FILE" ]]; then
  TTYD_PID="$TTYD_PID" PROXY_PID="$PROXY_PID" RUNTIME_DIR="$RUNTIME_DIR" "$CLEANUP_SCRIPT" || true
  echo "Proxy failed to start" >&2
  echo "See $PROXY_LOG_FILE" >&2
  exit 1
fi

PROXY_JSON="$(cat "$PROXY_INFO_FILE")"
PROXY_PORT="$(printf '%s' "$PROXY_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["port"])')"

if ! kill -0 "$TTYD_PID" 2>/dev/null; then
  PROXY_PID="$PROXY_PID" RUNTIME_DIR="$RUNTIME_DIR" "$CLEANUP_SCRIPT" || true
  echo "ttyd exited unexpectedly" >&2
  exit 1
fi

if ! kill -0 "$PROXY_PID" 2>/dev/null; then
  TTYD_PID="$TTYD_PID" RUNTIME_DIR="$RUNTIME_DIR" "$CLEANUP_SCRIPT" || true
  echo "proxy exited unexpectedly" >&2
  echo "See $PROXY_LOG_FILE" >&2
  exit 1
fi

TTL_SECONDS="$((TTL_MINUTES * 60))"
nohup bash -lc "sleep '$TTL_SECONDS'; TTYD_PID='$TTYD_PID' PROXY_PID='$PROXY_PID' RUNTIME_DIR='$RUNTIME_DIR' '$CLEANUP_SCRIPT'" >/dev/null 2>&1 &
CLEANUP_WATCHER_PID=$!

echo "CLEANUP_WATCHER_PID=$CLEANUP_WATCHER_PID" >> "$METADATA_FILE"

if [[ -n "$CLIENT_IP" && "$HOST" != "127.0.0.1" ]]; then
  UFW_ALLOW_CMD="sudo ufw allow from $CLIENT_IP to any port $PROXY_PORT proto tcp"
  UFW_DELETE_CMD="sudo ufw delete allow from $CLIENT_IP to any port $PROXY_PORT proto tcp"
else
  UFW_ALLOW_CMD=""
  UFW_DELETE_CMD=""
fi

if [[ "$HOST" == "127.0.0.1" ]]; then
  NOTE="Local only. URL token is one-shot. Proxy enforces expected host/origin and TTL cleanup."
else
  NOTE="LAN-exposed on $HOST:$PROXY_PORT with one-shot URL token. Restrict firewall to the client IP only and do not expose publicly."
fi

cat <<EOF
READY=1
SESSION_NAME=$SESSION_NAME
HOST=$HOST
PORT=$PROXY_PORT
URL=http://$HOST:$PROXY_PORT/?token=$ACCESS_TOKEN
EXPIRES_AT=$EXPIRES_AT
TTYD_PID=$TTYD_PID
TTYD_PORT=$UPSTREAM_PORT
PROXY_PID=$PROXY_PID
CLEANUP_WATCHER_PID=$CLEANUP_WATCHER_PID
RUNTIME_DIR=$RUNTIME_DIR
CLEANUP_CMD=TTYD_PID=$TTYD_PID PROXY_PID=$PROXY_PID RUNTIME_DIR=$RUNTIME_DIR $CLEANUP_SCRIPT
PROXY_JSON=$PROXY_JSON
BIND_SCOPE=$BIND_SCOPE
CLIENT_IP=$CLIENT_IP
EXPECTED_HOST=$EXPECTED_HOST
EXPECTED_ORIGIN=$EXPECTED_ORIGIN
COOKIE_SECURE=$COOKIE_SECURE
UFW_ALLOW_CMD=$UFW_ALLOW_CMD
UFW_DELETE_CMD=$UFW_DELETE_CMD
NOTE=$NOTE
EOF
