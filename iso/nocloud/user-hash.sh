#!/usr/bin/env bash
# user-hash.sh — hash SHA-512 du mot de passe de l'utilisateur ubun.
# Fichier SÉPARÉ de user-data (voir gen-autoinstall.sh) : ainsi le hash ne
# finit pas dans /var/log/installer/autoinstall-user-data du système installé.
# Rempli par iso/set-secrets.sh. Placeholder d'origine :
export UBUNTURIRI_USER_HASH='CHANGEME_PASSWORD_HASH_SHA512'
