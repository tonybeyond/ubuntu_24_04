#!/usr/bin/env bash
# install-brave.sh — Brave Origin (navigateur par défaut d'ubunturiri).
#
# Brave n'est pas dans les dépôts Ubuntu : on ajoute le dépôt APT officiel de
# Brave Software (signé, mis à jour par apt ensuite). Édition « origin » —
# sans Brave Rewards/Wallet/IA — gratuite sur Linux (même choix que fedoriri).
# Idempotent : ne refait rien si le paquet est déjà installé.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

KEYRING="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
LIST="/etc/apt/sources.list.d/brave-browser-release.list"

use_help=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) echo "Usage : $0 [--dry-run|--help]"; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done
finalize_flags

require_root
require_cmd curl gpg apt-get

if dpkg-query -W brave-browser >/dev/null 2>&1; then
  log "Brave déjà installé — rien à faire"
  exit 0
fi

if [ ! -f "$KEYRING" ]; then
  run curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    -o "$KEYRING"
  [ "$DRY_RUN" -eq 1 ] || chmod 0644 "$KEYRING"
fi

if [ ! -f "$LIST" ]; then
  echo "deb [signed-by=$KEYRING arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | run tee "$LIST" >/dev/null
fi

run apt-get update -qq
run apt-get install -y brave-browser

# Navigateur par défaut (xdg) pour l'utilisateur poste.
TARGET_USER="$(detect_target_user)"
if [ -n "$TARGET_USER" ] && command -v xdg-settings >/dev/null 2>&1; then
  run sudo -u "$TARGET_USER" xdg-settings set default-web-browser brave-browser.desktop || true
fi
log "Brave installé (dépôt apt actif — mises à jour par apt)"
