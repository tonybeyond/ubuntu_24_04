#!/usr/bin/env bash
# luks-passphrase.sh — secret LUKS d'ubunturiri, SÉPARÉ de user-data.
#
# Pourquoi un fichier à part : subiquity recopie le user-data complet dans
# /var/log/installer/autoinstall-user-data du système installé. Y mettre la
# phrase LUKS la laisserait sur le disque en clair et lisible ; la garder
# ici permet de la lire à l'installation puis de la SUPPRIMER (late-commands
# shred -u).
#
# Rempli par iso/set-secrets.sh (mode 0600). Placeholder d'origine :
export UBUNTURIRI_LUKS='CHANGEME_LUKS_PASSPHRASE'
