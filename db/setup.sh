#!/usr/bin/env bash
# Database tier setup for the Peaks demo.
#
# 1. Makes mongod listen on the network so the Node.js VM can reach it
#    (Ubuntu packages bind to 127.0.0.1 only by default).
# 2. Loads the seed data from seed.js into demodb.peaks.
#
# Usage (on the MongoDB VM, after MongoDB is installed):
#     sudo ./setup.sh
#
# Optional environment variables:
#     MONGODB_BIND_IP    address(es) for mongod to listen on   (default: 0.0.0.0)
#     NODEJS_IP_ADDRESS  if ufw is active, allow 27017/tcp from this address only
set -euo pipefail
cd "$(dirname "$0")"

BIND_IP="${MONGODB_BIND_IP:-0.0.0.0}"
CONF=/etc/mongod.conf

# The seed step below connects over loopback, so keep 127.0.0.1 in the list
# when a specific interface address was given instead of 0.0.0.0.
case ",$BIND_IP," in
    *,0.0.0.0,*|*,127.0.0.1,*|*,localhost,*) ;;
    *) BIND_IP="127.0.0.1,$BIND_IP" ;;
esac

# --- 1. network binding -----------------------------------------------------
if [ -f "$CONF" ]; then
    if grep -qE '^\s*bindIp:' "$CONF"; then                      # YAML config (mongodb-org)
        sed -i -E "s/^(\s*bindIp:).*/\1 $BIND_IP/" "$CONF"
    elif grep -qE '^\s*bind_ip\s*=' "$CONF"; then                # legacy ini-style config
        sed -i -E "s/^(\s*bind_ip\s*=).*/\1 $BIND_IP/" "$CONF"
    else
        echo "WARNING: no bindIp setting found in $CONF; add 'net.bindIp: $BIND_IP' manually." >&2
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable mongod >/dev/null 2>&1 || true
        systemctl restart mongod
    fi
    echo "mongod configured to listen on $BIND_IP"
else
    echo "WARNING: $CONF not found; skipping bindIp configuration." >&2
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if [ -n "${NODEJS_IP_ADDRESS:-}" ]; then
        ufw allow from "$NODEJS_IP_ADDRESS" to any port 27017 proto tcp
    else
        echo "WARNING: ufw is active. Allow 27017/tcp from the Node.js VM, e.g.:" >&2
        echo "         sudo ufw allow from <nodejs-ip> to any port 27017 proto tcp" >&2
    fi
fi

# --- 2. seed data -------------------------------------------------------------
if command -v mongosh >/dev/null 2>&1; then
    MONGO_SHELL=mongosh
elif command -v mongo >/dev/null 2>&1; then
    MONGO_SHELL=mongo
else
    echo "ERROR: neither 'mongosh' nor 'mongo' shell found in PATH." >&2
    exit 1
fi

echo -n "Waiting for mongod on 127.0.0.1:27017 "
for _ in $(seq 1 30); do
    if $MONGO_SHELL --quiet --host 127.0.0.1 --eval 'db.runCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
        echo "ready."
        break
    fi
    echo -n "."
    sleep 2
done

$MONGO_SHELL --quiet --host 127.0.0.1 seed.js
echo -n "demodb.peaks document count: "
$MONGO_SHELL --quiet --host 127.0.0.1 --eval 'db.getSiblingDB("demodb").peaks.countDocuments()'
