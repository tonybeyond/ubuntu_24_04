# shellcheck shell=bash
# Bibliothèque commune des scripts ubunturiri — portage Ubuntu de
# fedoriri/scripts/lib/common.sh.
# À sourcer, jamais à exécuter. Tous les scripts qui la sourcent obtiennent :
#   - la gestion --help/--dry-run homogène (variables HELP/DRY_RUN)
#   - log/warn/die
#   - run() : exécute ou affiche selon --dry-run
#   - require_root, require_cmd, wait_network
#   - detect_target_user : l'utilisateur "poste" (ubun par défaut)

set -euo pipefail

UBUNTURIRI_STATE_DIR="${UBUNTURIRI_STATE_DIR:-/var/lib/ubunturiri}"
UBUNTURIRI_SHARE_DIR="${UBUNTURIRI_SHARE_DIR:-/usr/share/ubunturiri}"

DRY_RUN=0
# Tableau à propager aux sous-scripts ("${DRY_FLAG[@]}") ; rempli par
# finalize_flags après l'analyse des options.
# shellcheck disable=SC2034
DRY_FLAG=()
# shellcheck disable=SC2034
finalize_flags() {
  if [ "$DRY_RUN" -eq 1 ]; then DRY_FLAG=(--dry-run); fi
}

log()  { printf '\033[1;34m[ubunturiri]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ubunturiri][attention]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ubunturiri][erreur]\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\033[0;36m[dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

require_root() {
  if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    die "ce script doit être lancé en root (ou avec --dry-run)"
  fi
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "commande requise absente : $c"
  done
}

# Attente réseau par HTTP (l'ICMP/ping est souvent filtré).
wait_network() {
  local timeout_s="${1:-300}" waited=0
  while [ "$waited" -lt "$timeout_s" ]; do
    if curl -fsS --max-time 5 -o /dev/null https://archive.ubuntu.com/ 2>/dev/null; then
      return 0
    fi
    sleep 5; waited=$((waited + 5))
  done
  return 1
}

# L'utilisateur "poste" : UBUNTURIRI_USER en priorité, sinon ubun s'il existe.
detect_target_user() {
  if [ -n "${UBUNTURIRI_USER:-}" ]; then printf '%s' "$UBUNTURIRI_USER"; return; fi
  if id ubun >/dev/null 2>&1; then printf 'ubun'; return; fi
  # Dernier recours : premier utilisateur de /home avec un UID >= 1000.
  local u
  for u in /home/*; do
    u="$(basename "$u")"
    if [ "$(id -u "$u" 2>/dev/null || echo 0)" -ge 1000 ]; then printf '%s' "$u"; return; fi
  done
  return 1
}
