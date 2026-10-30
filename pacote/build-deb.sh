#!/usr/bin/env bash
# Gera o .deb do edge-agent em dist/. Uso: build-deb.sh <versão>
set -euo pipefail
VERSION=${1:?uso: build-deb.sh <versão>}
[[ "$VERSION" =~ ^[0-9][0-9A-Za-z.+~-]*$ ]] || { echo "versão inválida: $VERSION" >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")" && pwd)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
chmod 0755 "$STAGE"
install -D -m 0755 "$ROOT/edge-agent.sh" "$STAGE/usr/bin/edge-agent"
install -D -m 0644 "$ROOT/edge-agent.service" "$STAGE/lib/systemd/system/edge-agent.service"
install -d -m 0755 "$STAGE/DEBIAN"
sed "s/@VERSION@/$VERSION/" "$ROOT/control.in" > "$STAGE/DEBIAN/control"
mkdir -p dist
dpkg-deb --build --root-owner-group "$STAGE" "dist/edge-agent_${VERSION}_all.deb"
