#!/usr/bin/env bash
# Rebuild web.tar.gz, db.tar.gz and nodejs-app.tar.gz from the source directories
# web/, db/ and nodejs-app/. Files are placed at the root of each archive (no
# leading directory), owned by root, with macOS metadata stripped.
set -euo pipefail
cd "$(dirname "$0")"

export COPYFILE_DISABLE=1   # no ._* AppleDouble files from macOS tar

if tar --version 2>/dev/null | grep -q 'GNU tar'; then
    OWNER_FLAGS=(--owner=0 --group=0 --numeric-owner)
else
    OWNER_FLAGS=(--uid 0 --gid 0 --uname root --gname root)
fi

build() {
    local archive="$1" dir="$2"
    local entries
    entries=$(cd "$dir" && ls -A | grep -v -E '^(node_modules|\.DS_Store)$' | sort)
    # shellcheck disable=SC2086
    tar czf "$archive" --no-xattrs --exclude='.DS_Store' --exclude='node_modules' \
        "${OWNER_FLAGS[@]}" -C "$dir" $entries
    printf '%-20s %8d bytes  (%d entries)\n' "$archive" "$(wc -c < "$archive")" "$(tar tzf "$archive" | wc -l)"
}

build web.tar.gz        web
build db.tar.gz         db
build nodejs-app.tar.gz nodejs-app
