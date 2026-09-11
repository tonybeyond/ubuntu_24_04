#!/usr/bin/env bash
# gen-autoinstall.sh — génère /autoinstall.yaml à l'installation.
#
# Rôles :
#   1. détecter le disque cible (le plus gros, média d'installation exclu) —
#      un nom codé en dur casserait selon l'hôte (vda Proxmox, sda USB,
#      nvme0n1 métal) ;
#   2. lire les secrets depuis les fichiers séparés (user-hash.sh,
#      luks-passphrase.sh) — user-data ne les transporte pas, et rien ne
#      doit finir dans /var/log/installer/autoinstall-user-data ;
#   3. écrire /autoinstall.yaml complet (LUKS2 via keyfile temporaire
#      root:root 0400, effacé en late-commands).

set -euo pipefail
SEED="${SEED_DIR:-/cdrom/nocloud}"

log() { echo "ubunturiri: $*" | tee /dev/tty1 2>/dev/null || echo "ubunturiri: $*"; }
die() { echo "ubunturiri ERREUR: $*" > /dev/tty1 2>/dev/null || echo "ubunturiri ERREUR: $*" >&2; exit 1; }

  # 1. Déjà monté sur /cdrom (cas subiquity normal) : ne rien faire.
  # 2. Sinon, chercher la seed en montant les candidats (rom, partitions) —
  #    pas par LABEL : sur une clé USB dd, le label ISO est dupliqué sur sda
  #    ET sda1 et le montage par label échoue (constaté sur matériel réel
  #    dans fedoriri).
  if [ ! -f "$SEED/user-hash.sh" ]; then
    mkdir -p /tmp/ubunturiri-seed
    for d in $(lsblk -pnro NAME,TYPE | awk '$2=="rom" || $2=="part" {print $1}'); do
      [ -b "$d" ] || continue
      mount -o ro "$d" /tmp/ubunturiri-seed 2>/dev/null || continue
      if [ -f /tmp/ubunturiri-seed/nocloud/user-hash.sh ]; then
        SEED=/tmp/ubunturiri-seed/nocloud
        break
      fi
      umount /tmp/ubunturiri-seed
    done
  fi
# shellcheck source=/dev/null
. "$SEED/user-hash.sh"       || die "user-hash.sh absent (build_iso a-t-il copié la seed ?)"
# shellcheck source=/dev/null
. "$SEED/luks-passphrase.sh" || die "luks-passphrase.sh absent"

[ -n "${UBUNTURIRI_USER_HASH:-}" ] \
  && [ "$UBUNTURIRI_USER_HASH" != "CHANGEME_PASSWORD_HASH_SHA512" ] \
  || die "hash du mot de passe non remplacé — lancez iso/set-secrets.sh"
[ -n "${UBUNTURIRI_LUKS:-}" ] \
  && [ "$UBUNTURIRI_LUKS" != "CHANGEME_LUKS_PASSPHRASE" ] \
  || die "phrase LUKS non remplacée — lancez iso/set-secrets.sh"

umask 077
printf '%s' "$UBUNTURIRI_LUKS" > /tmp/luks-passphrase
unset UBUNTURIRI_LUKS

# --- Disque cible : le plus gros disque, jamais un rom/USB de boot -----------
DISK=""
BEST=0
while read -r name type size rmflag; do
  [ "$type" = "disk" ] || continue
  [ "$rmflag" = "1" ] && continue   # exclut la clé USB amovible d'installation
  # Jamais le disque qui porte le média d'installation (ni aucun de ses
  # enfants : sda1 monté sur /cdrom ⇒ sda exclu).
  skip=0
  for child in /dev/${name}*; do
    grep -qs "^${child} " /proc/mounts && { skip=1; break; }
  done
  [ "$skip" -eq 1 ] && continue
  if [ -z "$DISK" ] || [ "$size" -gt "$BEST" ]; then DISK="$name"; BEST="$size"; fi
done < <(lsblk -b -dno NAME,TYPE,SIZE,RM)
[ -n "$DISK" ] || die "aucun disque cible détecté"
log "disque cible : /dev/$DISK (effacement TOTAL, LUKS2)"

# --- /autoinstall.yaml --------------------------------------------------------
# ⚠️ EFFACE LE DISQUE SANS CONFIRMATION. Voulu : installation non interactive.
cat > /autoinstall.yaml <<EOF
autoinstall:
  version: 1

  locale: en_US.UTF-8
  keyboard:
    layout: ch
    variant: fr
  timezone: Europe/Zurich

  identity:
    hostname: ubunturiri
    username: ubun
    realname: 'ubun'
    password: '${UBUNTURIRI_USER_HASH}'

  # Stockage : disque entier, GPT, ESP 1 Gio, reste en conteneur LUKS2/ext4.
  storage:
    grub:
      reorder_uefi: false
    config:
      - {id: disk0, type: disk, ptable: gpt, path: /dev/${DISK}, grub_device: true, wipe: superblock-recursive}
      - {id: part-esp, type: partition, device: disk0, size: 1073741824, flag: boot}
      - {id: fs-esp, type: format, volume: part-esp, fstype: fat32}
      - {id: part-luks, type: partition, device: disk0, size: -1}
      - id: dm-crypt
        type: dm_crypt
        volume: part-luks
        keyfile: /tmp/luks-passphrase
      - {id: fs-root, type: format, volume: dm-crypt, fstype: ext4}
      - {id: mnt-root, type: mount, path: /, device: fs-root}
      - {id: mnt-esp, type: mount, path: /boot/efi, device: fs-esp}

  packages:
    - ubuntu-desktop-minimal
    - gnome-shell-extension-pop-shell
    - gnome-shell-extension-manager
    - gnome-tweaks
    - alacritty
    - network-manager
    - openssh-server
    - curl
    - ca-certificates

  updates: security

  ssh:
    install-server: true
    allow-pw: false

  late-commands:
    # Payload → /opt/ubunturiri dans la cible, puis configuration en chroot.
    - curtin in-target --target=/target -- install -d -m 0755 /opt/ubunturiri
    - cp -r /cdrom/nocloud/payload/. /target/opt/ubunturiri/
    - curtin in-target --target=/target -- bash /target/opt/ubunturiri/scripts/late-chroot.sh
    # La phrase LUKS a fait son office : elle ne doit survivre nulle part.
    - shred -u /tmp/luks-passphrase 2>/dev/null || rm -f /tmp/luks-passphrase

  shutdown: reboot
EOF

# Garde-fou : le fichier généré ne doit JAMAIS contenir la phrase LUKS
# (elle ne vit que dans /tmp/luks-passphrase, effacé ci-dessus en fin
# d'installation par les late-commands).
grep -q 'keyfile: /tmp/luks-passphrase' /autoinstall.yaml \
  || die "le keyfile n'est pas référencé dans /autoinstall.yaml"

log "autoinstall généré — démarrage de subiquity"
