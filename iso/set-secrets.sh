#!/usr/bin/env bash
# set-secrets.sh — remplit les deux secrets de l'autoinstall de façon guidée :
#   1. le HASH du mot de passe de l'utilisateur ubun
#      (nocloud/user-hash.sh, placeholder CHANGEME_PASSWORD_HASH_SHA512) ;
#   2. la phrase de passe LUKS (demandée à CHAQUE démarrage)
#      (nocloud/luks-passphrase.sh, placeholder CHANGEME_LUKS_PASSPHRASE).
#
# Les deux secrets vivent dans des FICHIERS SÉPARÉS de user-data : subiquity
# recopie user-data dans /var/log/installer/ du système installé, ces deux
# fichiers-là n'y transitent jamais (lus à l'installation par
# gen-autoinstall.sh ; la phrase LUKS est ensuite effacée).
#
# Rien n'est affiché à l'écran ni passé en argument (pas de trace dans
# l'historique). Idempotent : un placeholder déjà remplacé n'est pas retouché.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$SCRIPT_DIR/nocloud/user-data"
LUKS_FILE="$SCRIPT_DIR/nocloud/luks-passphrase.sh"

command -v openssl >/dev/null 2>&1 || { echo "openssl est requis" >&2; exit 1; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage : $0   (interactif, aucun argument)"
  exit 0
fi

ask_secret() {
  local prompt="$1" s1 s2
  while :; do
    read -r -s -p "$prompt : " s1; echo >&2
    read -r -s -p "$prompt (confirmation) : " s2; echo >&2
    [ -n "$s1" ] || { echo "vide — recommencez" >&2; continue; }
    [ "$s1" = "$s2" ] || { echo "les deux saisies diffèrent — recommencez" >&2; continue; }
    printf '%s' "$s1"
    return
  done
}

# --- 1. Mot de passe utilisateur → hash SHA-512 -----------------------------
HASH_FILE="$SCRIPT_DIR/nocloud/user-hash.sh"
if grep -q 'CHANGEME_PASSWORD_HASH_SHA512' "$HASH_FILE"; then
  PW="$(ask_secret "Mot de passe de l'utilisateur ubun")"
  HASH="$(printf '%s' "$PW" | openssl passwd -6 -stdin)"
  unset PW
  sed -i.bak "s|CHANGEME_PASSWORD_HASH_SHA512|${HASH}|" "$HASH_FILE" && rm -f "$HASH_FILE.bak"
  chmod 0600 "$HASH_FILE"
  echo "→ hash posé dans nocloud/user-hash.sh (mode 0600)"
else
  echo "→ nocloud/user-hash.sh : déjà renseigné, rien à faire"
fi

# --- 2. Phrase de passe LUKS ------------------------------------------------
# Stockée dans un FICHIER SÉPARÉ copié sur l'ISO et lu par l'early-command de
# subiquity, puis SUPPRIMÉE du disque à la fin de l'autoinstall : elle ne
# reste pas dans /var/log/installer/autoinstall-user-data.
if grep -q 'CHANGEME_LUKS_PASSPHRASE' "$LUKS_FILE"; then
  while :; do
    LUKS="$(ask_secret "Phrase de passe LUKS (demandée à chaque démarrage)")"
    case "$LUKS" in
      *'|'*|*'\'*) echo "évitez les caractères | et \\ — recommencez" >&2 ;;
      *\"*|*\$*) echo "évitez \" et \$ (interpolation shell) — recommencez" >&2 ;;
      *\'*) echo "évitez le caractère ' — recommencez" >&2 ;;
      *) break ;;
    esac
  done
  sed -i.bak "s|CHANGEME_LUKS_PASSPHRASE|${LUKS}|" "$LUKS_FILE" && rm -f "$LUKS_FILE.bak"
  chmod 0600 "$LUKS_FILE"
  unset LUKS
  echo "→ phrase LUKS posée dans nocloud/luks-passphrase.sh (mode 0600)"
else
  echo "→ nocloud/luks-passphrase.sh : déjà renseignée, rien à faire"
fi

cat <<'EOF'

Secrets en place. Rappels :
  - NE COMMITEZ PAS ces deux fichiers modifiés (git ne doit jamais voir les
    secrets) : git restore iso/nocloud/user-hash.sh iso/nocloud/luks-passphrase.sh
    pour revenir aux placeholders ;
  - l'ISO produite contiendra ces secrets → ne pas la diffuser ;
  - après installation, ajoutez une NOUVELLE phrase LUKS et supprimez celle
    de l'ISO : cryptsetup luksChangeKey /dev/<partition-luks>
EOF
