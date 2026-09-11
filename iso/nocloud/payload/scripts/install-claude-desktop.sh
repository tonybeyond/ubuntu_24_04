#!/usr/bin/env bash
# install-claude-desktop.sh — Claude Desktop pour Linux (AppImage communautaire).
#
# Portage Ubuntu de fedoriri (même script, mêmes sources). Claude Desktop
# n'a pas de build Linux officiel : le projet communautaire
# claude-desktop-debian publie des releases AppImage/deb — on prend le .deb
# amd64 de la dernière release (résolue via l'API GitHub, sha256 si publié).

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

API="https://api.github.com/repos/wimpysworld/claude-desktop-debian/releases/latest"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) echo "Usage : $0 [--dry-run|--help]"; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done
finalize_flags

if dpkg-query -W claude-desktop >/dev/null 2>&1; then
  log "Claude Desktop déjà installé — rien à faire"
  exit 0
fi

require_root
require_cmd curl dpkg

release="$(curl -fsSL "$API")" || die "API GitHub inaccessible"
# Dernier .deb amd64 de la release.
deb_url="$(printf '%s' "$release" \
  | grep -oE '"browser_download_url":\s*"[^"]*amd64\.deb"' \
  | head -1 | sed -E 's/.*"(https[^"]*\.deb)".*/\1/')"
[ -n "$deb_url" ] || die "aucun .deb amd64 dans la dernière release"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
log "téléchargement : $deb_url"
run curl -fL --retry 3 -o "$tmp/claude-desktop.deb" "$deb_url"
run dpkg -i "$tmp/claude-desktop.deb" || apt-get install -y -f --no-install-recommends
log "Claude Desktop installé ✔"
