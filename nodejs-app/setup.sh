#!/usr/bin/env bash
# Application tier setup for the Peaks demo.
#
# Installs npm dependencies, copies the app to APP_DIR, and registers it as the
# systemd service "peaks-api" listening on PORT (default 3000).
#
# Usage (on the Node.js VM, after Node.js 16.20.1+ and npm are installed):
#     sudo MONGODB_HOST=<mongodb-vm-ip> ./setup.sh
#
# Environment variables:
#     MONGODB_HOST   (required) IP or hostname of the MongoDB VM
#     MONGODB_PORT   MongoDB port                      (default: 27017)
#     MONGODB_DB     database name                     (default: demodb)
#     PORT           port for the API to listen on     (default: 3000)
#     APP_DIR        install location                  (default: /opt/peaks-api)
#     NODE_BIN       path to the node binary, if node is not on root's PATH
#                    (e.g. /usr/local/n/versions/node/17.9.1/bin/node). Must be
#                    readable by the "peaks" service user, so a system-wide
#                    install (/usr, /usr/local, /opt, /snap) rather than a
#                    per-user nvm install.
set -euo pipefail

# sudo resets PATH to a fixed list, so a Node.js tarball unpacked somewhere like
# /usr/local/bin/nodejs is invisible here. Look in the usual places unless
# NODE_BIN says where it is.
if [ -z "${NODE_BIN:-}" ] && ! command -v node >/dev/null 2>&1; then
    for candidate in /usr/local/bin/nodejs/bin/node /usr/local/nodejs/bin/node \
                     /usr/local/node/bin/node /opt/nodejs/bin/node /opt/node/bin/node \
                     /snap/bin/node /usr/local/lib/nodejs/bin/node; do
        if [ -x "$candidate" ]; then NODE_BIN="$candidate"; break; fi
    done
fi
if [ -n "${NODE_BIN:-}" ]; then
    [ -x "$NODE_BIN" ] || { echo "ERROR: NODE_BIN=$NODE_BIN is not executable" >&2; exit 1; }
    export PATH="$(dirname "$NODE_BIN"):$PATH"
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-/opt/peaks-api}"
PORT="${PORT:-3000}"
: "${MONGODB_HOST:?Set MONGODB_HOST to the IP or hostname of the MongoDB VM}"

command -v node >/dev/null 2>&1 || { echo "ERROR: node not found in PATH" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "ERROR: npm not found in PATH" >&2; exit 1; }
NODE_BIN="$(command -v node)"
# mongoose 8 needs Node.js 16.20.1 or newer
if ! node -e 'var v=process.versions.node.split(".").map(Number); process.exit((v[0]>16 || (v[0]===16 && (v[1]>20 || (v[1]===20 && v[2]>=1)))) ? 0 : 1)'; then
    echo "ERROR: Node.js 16.20.1 or newer is required (mongoose 8); found $(node -v)." >&2
    echo "       Install a current release, e.g. from https://deb.nodesource.com or via 'snap install node --classic'." >&2
    exit 1
fi
echo "Using $NODE_BIN ($(node -v))"

# --- application files --------------------------------------------------------
id -u peaks >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin peaks
mkdir -p "$APP_DIR"
if [ "$SRC" != "$APP_DIR" ]; then
    cp -R "$SRC"/. "$APP_DIR"/
fi
cd "$APP_DIR"

if [ -f package-lock.json ]; then
    npm ci --omit=dev --no-audit --no-fund
else
    npm install --omit=dev --no-audit --no-fund
fi
chown -R peaks:peaks "$APP_DIR"

# --- service --------------------------------------------------------------------
cat > /etc/default/peaks-api <<ENV
# Environment for the peaks-api systemd service (written by setup.sh)
MONGODB_HOST=$MONGODB_HOST
MONGODB_PORT=${MONGODB_PORT:-27017}
MONGODB_DB=${MONGODB_DB:-demodb}
PORT=$PORT
ENV

sed -e "s|^ExecStart=.*|ExecStart=$NODE_BIN app.js|" \
    -e "s|^WorkingDirectory=.*|WorkingDirectory=$APP_DIR|" \
    "$APP_DIR/peaks-api.service" > /etc/systemd/system/peaks-api.service
systemctl daemon-reload
systemctl enable peaks-api >/dev/null
systemctl restart peaks-api

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$PORT"/tcp
fi

# --- verify ---------------------------------------------------------------------
echo -n "Waiting for the API on 127.0.0.1:$PORT "
for _ in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then echo "ready."; break; fi
    echo -n "."; sleep 1
done
echo "Health (503 until MongoDB at $MONGODB_HOST is reachable):"
curl -sS "http://127.0.0.1:$PORT/api/health" || true
echo
echo "Service status: systemctl status peaks-api    Logs: journalctl -u peaks-api -f"
