#!/usr/bin/env bash
# Web tier setup for the Peaks demo.
#
# Copies the site into WEB_ROOT, fills in the placeholders on the page, and
# installs an NGINX site that proxies /api/ to the Node.js VM.
#
# Usage (on the NGINX VM, after nginx is installed):
#     sudo NODEJS_IP_ADDRESS=<nodejs-vm-ip> ./setup.sh
#
# Environment variables:
#     NODEJS_IP_ADDRESS  (required) IP or hostname of the Node.js VM
#     NODEJS_PORT        port the Node.js API listens on   (default: 3000)
#     APP_TITLE          heading shown at the top of the page (default: Nutanix Demo)
#     WEB_IP_ADDRESS     shown on the page                  (default: this host's first IP)
#     WEB_SERVER_NAME    shown on the page                  (default: this host's hostname)
#     WEB_ROOT           where to install the site          (default: /var/www/peaks)
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
WEB_ROOT="${WEB_ROOT:-/var/www/peaks}"
NODEJS_PORT="${NODEJS_PORT:-3000}"
: "${NODEJS_IP_ADDRESS:?Set NODEJS_IP_ADDRESS to the IP or hostname of the Node.js VM}"
WEB_IP_ADDRESS="${WEB_IP_ADDRESS:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
WEB_SERVER_NAME="${WEB_SERVER_NAME:-$(hostname)}"
APP_TITLE="${APP_TITLE:-Nutanix Demo}"

# Escape a value for use as HTML text and as a sed replacement string.
sed_html_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/[\|&]/\\&/g'
}

command -v nginx >/dev/null 2>&1 || { echo "ERROR: nginx not found in PATH" >&2; exit 1; }

# --- site files -----------------------------------------------------------------
mkdir -p "$WEB_ROOT"
if [ "$SRC" != "$WEB_ROOT" ]; then
    for item in index.html css js images; do
        rm -rf "$WEB_ROOT/$item"
        cp -R "$SRC/$item" "$WEB_ROOT/"
    done
fi
sed -e "s|WEB_IP_ADDRESS|$WEB_IP_ADDRESS|g" \
    -e "s|WEB_SERVER_NAME|$WEB_SERVER_NAME|g" \
    -e "s|APP_TITLE|$(sed_html_escape "$APP_TITLE")|g" \
    "$WEB_ROOT/index.html" > "$WEB_ROOT/index.html.tmp" && mv "$WEB_ROOT/index.html.tmp" "$WEB_ROOT/index.html"
if id -u www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "$WEB_ROOT"
fi

# --- nginx site -----------------------------------------------------------------
if [ -d /etc/nginx/sites-available ]; then                       # Debian/Ubuntu layout
    SITE=/etc/nginx/sites-available/peaks
    sed -e "s|NODEJS_IP_ADDRESS:3000|$NODEJS_IP_ADDRESS:$NODEJS_PORT|" \
        -e "s|root /var/www/peaks;|root $WEB_ROOT;|" "$SRC/nginx/peaks.conf" > "$SITE"
    mkdir -p /etc/nginx/sites-enabled
    ln -sf "$SITE" /etc/nginx/sites-enabled/peaks
    rm -f /etc/nginx/sites-enabled/default                       # avoid duplicate default_server
else                                                              # conf.d layout
    sed -e "s|NODEJS_IP_ADDRESS:3000|$NODEJS_IP_ADDRESS:$NODEJS_PORT|" \
        -e "s|root /var/www/peaks;|root $WEB_ROOT;|" "$SRC/nginx/peaks.conf" > /etc/nginx/conf.d/peaks.conf
    rm -f /etc/nginx/conf.d/default.conf
fi

nginx -t
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 80/tcp
fi

# --- verify -----------------------------------------------------------------------
echo "Site installed. Page:  http://$WEB_IP_ADDRESS/"
echo -n "Local page check:      "; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
echo -n "API via proxy check:   "; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/api/health || true
echo "(API check returns 200 once the Node.js tier is up and connected to MongoDB, 503 if Node.js is up but MongoDB is not, 502 if Node.js is unreachable.)"
