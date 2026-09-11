#!/usr/bin/env bash
# shellcheck disable=SC2034
# first-boot.sh — point d'entrée de ubunturiri-first-boot.service.
#
# Rôle : attendre le réseau, dérouler post-install.sh, poser le témoin, puis
# désarmer le service. Toute la logique métier est dans post-install.sh
# (rejouable à la main, idempotent) — portage Ubuntu de fedoriri.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h) echo "Usage : $0 [--dry-run|--help] — lancé par le service"; exit 0 ;;
    *) die "option inconnue : $arg" ;;
  esac
done
finalize_flags

require_root

log "===== ubunturiri : premier démarrage — installation en cours ====="
log "Cette étape télécharge Citrix, Brave et des paquets (plusieurs minutes)."

if ! wait_network 600; then
  # Sans réseau : pas de témoin → nouvelle tentative au prochain démarrage,
  # SAUF si un pool local suffit (install Citrix/Brave exige le réseau).
  die "réseau indisponible après 10 min — nouvelle tentative au prochain démarrage"
fi

"$SCRIPT_DIR/post-install.sh" "${DRY_FLAG[@]+"${DRY_FLAG[@]}"}"

run mkdir -p "$UBUNTURIRI_STATE_DIR"
run touch "$UBUNTURIRI_STATE_DIR/first-boot.done"
run systemctl disable ubunturiri-first-boot.service

log "===== ubunturiri : premier démarrage terminé — redémarrage conseillé ====="
