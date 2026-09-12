#!/usr/bin/env bash
# shellcheck disable=SC2034
# post-install.sh — orchestrateur de la post-installation ubunturiri.
#
# Portage Ubuntu de fedoriri/scripts/post-install.sh, SANS la partie Shadow.
# Idempotent : chaque étape vérifie son propre état ; rejouer ne casse rien.
#   - automatiquement, via first-boot.sh au premier démarrage ;
#   - à la main : sudo /opt/ubunturiri/scripts/post-install.sh

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SKIP_CITRIX=0
SKIP_BRAVE=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --skip-citrix   ne pas installer Citrix Workspace app
  --skip-brave    ne pas installer Brave
  --dry-run       affiche les commandes sans les exécuter
  --help          cette aide
Variable : UBUNTURIRI_USER=<login> pour cibler un autre utilisateur que ubun.
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-citrix) SKIP_CITRIX=1 ;;
    --skip-brave)  SKIP_BRAVE=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    --help|-h)     usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done
finalize_flags

require_root
require_cmd apt-get curl

TARGET_USER="$(detect_target_user)"
[ -n "$TARGET_USER" ] || die "impossible de déterminer l'utilisateur cible (UBUNTURIRI_USER=?)"
log "utilisateur cible : $TARGET_USER"

step() { log "--- $* ---"; }

# ---------------------------------------------------------------------------
step "Paquets complémentaires (pool local d'abord, réseau ensuite)"
# Le pool local de l'ISO est une source apt file:// ; apt la consulte avant
# le réseau, d'où une installation (hors ligne possible si le y pool couvre).
run apt-get update -qq || warn "apt update partiel — on poursuit"
run apt-get install -y --no-install-recommends \
    starship \
    fonts-jetbrains-mono \
    papirus-icon-theme \
  || warn "paquets complémentaires partiellement installés (réseau requis pour ceux absents du pool)"

# ---------------------------------------------------------------------------
step "Citrix Workspace app (ligne stable .deb, Xorg)"
if [ "$SKIP_CITRIX" -eq 0 ]; then
  run "$SCRIPT_DIR/install-citrix.sh" "${DRY_FLAG[@]+"${DRY_FLAG[@]}"}"
else
  log "→ sauté (--skip-citrix)"
fi

# ---------------------------------------------------------------------------
step "Brave (navigateur par défaut)"
if [ "$SKIP_BRAVE" -eq 0 ]; then
  run "$SCRIPT_DIR/install-brave.sh" "${DRY_FLAG[@]+"${DRY_FLAG[@]}"}"
else
  log "→ sauté (--skip-brave)"
fi

# ---------------------------------------------------------------------------
step "Thème par défaut (tokyo-night, si le moteur est présent)"
if [ -x /usr/local/bin/ubunturiri-render-theme ] && [ -d /usr/share/ubunturiri/themes ]; then
  # Appliqué en tant qu'utilisateur, sans rechargement (aucune session X).
  if [ -f "$SCRIPT_DIR/ubunturiri-theme-set" ]; then
    run sudo -u "$TARGET_USER" FEDORIRI_SHARE_DIR=/usr/share/ubunturiri \
        "$SCRIPT_DIR/ubunturiri-theme-set" --no-reload tokyo-night \
      || warn "application du thème échouée (non bloquant)"
  fi
else
  log "→ moteur de thème absent, étape sautée"
fi

step "Extension de tuilage (tiling-assistant noble + tentative Pop Shell)"
# Pop Shell n'est pas publié pour noble (GNOME 46) : ubuntu-tiling-assistant
# fournit le tiling MAINTENU. On tente en PLUS le vrai Pop Shell depuis la
# source communautaire la plus récente, best-effort (non bloquant).
if [ -d /etc/skel/.config/autostart ]; then
  cat > /etc/skel/.config/autostart/ubunturiri-tiling.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=ubunturiri : activer le tiling GNOME
Exec=gnome-extensions enable ubuntu-tiling-assistant@ubuntu.com
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Phase=Initialization
EOF
fi

log "post-installation terminée"
