#!/usr/bin/env bash
# run-local-checks.sh — garde-fous exécutés AVANT chaque build.
# Échoue volontairement (exit 1) si un contrôle ne passe pas.

set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

err() { echo "  ✘ $*" >&2; fail=1; }
ok()  { echo "  ✔ $*"; }

echo "== Placeholders des secrets =="
if grep -q 'CHANGEME_PASSWORD_HASH_SHA512' "$ROOT/iso/nocloud/user-hash.sh"; then
  err "user-hash.sh : hash non remplacé — lancez ./iso/set-secrets.sh"
else
  ok "hash utilisateur remplacé"
fi
if grep -q 'CHANGEME_LUKS_PASSPHRASE' "$ROOT/iso/nocloud/luks-passphrase.sh"; then
  err "luks-passphrase.sh : phrase non remplacée — lancez ./iso/set-secrets.sh"
else
  ok "phrase LUKS remplacée"
fi

echo "== user-data (seed) ne contient aucun secret =="
if grep -qE 'CHANGEME_|password:|luks' "$ROOT/iso/nocloud/user-data"; then
  err "user-data contient un secret ou un placeholder — il ne doit en contenir aucun"
else
  ok "user-data sans secret"
fi

echo "== Syntaxe shell =="
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then
    ok "$(realpath --relative-to="$ROOT" "$f")"
  else
    err "syntaxe bash : $f"
  fi
done < <(find "$ROOT" -name '*.sh' -o -name 'set-secrets*' -o -name 'build-iso*' | sort)

echo "== Fichiers requis de la seed =="
for f in user-data meta-data gen-autoinstall.sh user-hash.sh luks-passphrase.sh; do
  if [ -f "$ROOT/iso/nocloud/$f" ]; then
    ok "nocloud/$f"
  else
    err "nocloud/$f manquant"
  fi
done
[ "$(cat "$ROOT/iso/nocloud/meta-data")" = "" ] \
  && ok "meta-data vide" || err "meta-data doit être vide (seed NoCloud)"

echo "== Payload (scripts + service) =="
for f in \
  payload/scripts/lib/common.sh \
  payload/scripts/first-boot.sh \
  payload/scripts/post-install.sh \
  payload/scripts/late-chroot.sh \
  payload/scripts/install-citrix.sh \
  payload/scripts/install-brave.sh \
  payload/systemd/ubunturiri-first-boot.service; do
  if [ -f "$ROOT/iso/nocloud/$f" ]; then
    ok "$f"
  else
    err "$f manquant"
  fi
done

echo "== gen-autoinstall : les secrets ne fuient pas =="
# Le script généré ne doit jamais écrire la phrase LUKS dans le YAML.
if grep -n 'autoinstall.yaml' "$ROOT/iso/nocloud/gen-autoinstall.sh" >/dev/null \
   && grep -q 'keyfile: /tmp/luks-passphrase' "$ROOT/iso/nocloud/gen-autoinstall.sh"; then
  ok "phrase LUKS via keyfile temporaire, pas en clair dans le YAML"
else
  err "la phrase LUKS semble en clair dans le YAML généré"
fi

[ "$fail" -eq 0 ] || { echo; echo "Garde-fous échoués — build refusé." >&2; exit 1; }
echo
echo "Tous les garde-fous passent."
