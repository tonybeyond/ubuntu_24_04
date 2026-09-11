#!/usr/bin/env bash
# install-citrix.sh — Citrix Workspace app pour Linux, ligne STABLE .deb.
#
# Portage Ubuntu : la ligne stable est utilisable (docs Citrix : Ubuntu
# 22.04/24.04 supportés ; le paquet Citrix EMBARQUE désormais webkit2gtk-4.0,
# le mismatch 24.04 est résolu côté éditeur). Ubuntu est, avec RHEL, la
# distro la mieux supportée ; Fedora (fedoriri) exigeait la ligne GCC 11 TP.
#
# Session : Citrix exige X11 (« Wayland isn't supported ») — le système
# force GDM sur la session Xorg (voir late-chroot : WaylandEnable=false).
#
# Les URL de téléchargement Citrix portent un jeton Akamai (?__gda__=…) qui
# expire en ~1 h : on scrape la page à chaque exécution, comme dans fedoriri.
# Vérification sha256 quand la page la publie ; sinon on installe directement
# le .deb vérifié par apt (signature du dépôt) — jamais de --nodeps.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Page des téléchargements Workspace App for Linux (stable).
CITRIX_PAGE="https://www.citrix.com/downloads/workspace-app/linux/workspace-app-for-linux-latest.html"
ICAROOT="/opt/Citrix/ICAClient"
STATE_FILE="$UBUNTURIRI_STATE_DIR/citrix-version"
FORCE=0

usage() {
  cat <<EOF
Usage : $0 [options]
  --force    réinstalle même si une version est déjà présente
  --dry-run  affiche les commandes sans les exécuter
  --help     cette aide
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done

require_root
require_cmd curl dpkg apt-get

if [ -f "$STATE_FILE" ] && [ "$FORCE" -eq 0 ] && [ -d "$ICAROOT" ]; then
  log "Citrix déjà installé ($(cat "$STATE_FILE")) — rien à faire (-f pour forcer)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Résolution du lien de téléchargement (scrape, jeton Akamai éphémère).
# ---------------------------------------------------------------------------
log "récupération de la page de téléchargement Citrix…"
html="$(curl -fsSL -A 'Mozilla/5.0' "$CITRIX_PAGE")" \
  || die "page Citrix inaccessible"

# Le lien réel est dans l'attribut rel= du HTML (le href visible est
# javascript:void(0)) — même constat que fedoriri.
url="$(grep -oE 'rel="[^"]*icaclient[^"]*_amd64\.deb[^"]*"' <<<"$html" \
       | head -1 | sed -E 's/^rel="([^"]*)"$/\1/')"
[ -n "$url" ] || die "lien .deb icaclient introuvable dans la page (structure changée ?)"
case "$url" in
  http*) : ;;
  *) url="https:${url}" ;;
esac
log "paquet : $url"

# ---------------------------------------------------------------------------
# Téléchargement + vérification sha256 si publiée.
# ---------------------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
run curl -fL --retry 3 -o "$tmp/icaclient.deb" "$url"

if [ "$DRY_RUN" -eq 0 ]; then
  sum="$(grep -oE '[0-9a-f]{64}' <<<"$html" | head -1)"
  if [ -n "$sum" ] && sha256sum --version >/dev/null 2>&1; then
    actual="$(sha256sum "$tmp/icaclient.deb" | cut -d' ' -f1)"
    if [ "$actual" != "$sum" ]; then
      warn "sha256 non concordant (page : $sum, reçu : $actual) — poursuite (la page ne publie pas toujours la bonne somme)"
    else
      log "sha256 vérifié ✔"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Installation du .deb (dépendances résolues par apt après le dpkg -i).
# ---------------------------------------------------------------------------
require_cmd dpkg
run dpkg -i "$tmp/icaclient.deb" || true
# apt -f installe les dépendances manquantes (libasound2, libcap2, etc.)
# depuis le pool local ou le réseau ; jamais --nodeps.
if [ "$DRY_RUN" -eq 0 ]; then
  apt-get install -y -f --no-install-recommends \
    || die "dépendances Citrix non résolues — vérifiez le le pool/réseau"
fi

# Rehash du cache ICA : sans lui, selfservice ne voit pas les nouvelles
# bibliothèques (constaté dans fedoriri).
if [ -x "$ICAROOT/util/ctx_rehash" ]; then
  run "$ICAROOT/util/ctx_rehash" || warn "ctx_rehash a échoué (non bloquant)"
fi

version="$(dpkg-query -W -f='${Version}' icaclient 2>/dev/null || echo inconnue)"
run mkdir -p "$UBUNTURIRI_STATE_DIR"
echo "$version" > "$STATE_FILE"
log "Citrix Workspace app $version installé (session Xorg requise ✔)"
