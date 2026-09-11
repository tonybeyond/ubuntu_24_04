#!/usr/bin/env bash
# late-chroot.sh — exécuté EN CHROOT dans la cible par les late-commands de
# subiquity (curtin in-target). Y afflue le payload déjà copié dans
# /target/opt/ubunturiri.
#
# Ici : uniquement ce qui doit se passer dans le chroot d'installation
# (sources apt locales, dotfiles /etc/skel, session Xorg par défaut). Le
# travail lourd (Citrix, Brave, thèmes) est AU PREMIER BOOT par
# ubunturiri-first-boot.service — mêmes raisons que fedoriri : services
# non démarrables en chroot, pas de réseau garanti, etc.

set -euo pipefail

log() { echo "[ubunturiri-chroot] $*"; }

# --- Pool local de paquets : source apt file:// permanente ------------------
# Le pool de l'ISO est copié dans /opt/ubunturiri-pool (par gen-autoinstall)
# ou est monté ; ici on déclare la source pour que l'installation des
# paquets complémentaires au premier boot fonctionne SANS réseau.
if [ -d /opt/ubunturiri-pool ] && [ -s /opt/ubunturiri-pool/Packages.gz ]; then
  cat > /etc/apt/sources.list.d/ubunturiri-local.list <<'EOF'
deb [trusted=yes] file:///opt/ubunturiri-pool ./
EOF
  log "source apt locale : /opt/ubunturiri-pool ✔"
fi

# --- Locale : en_US.UTF-8 + formats fr_CH (dates, nombres, monnaie) ---------
cat > /etc/default/locale <<'EOF'
LANG=en_US.UTF-8
LC_TIME=fr_CH.UTF-8
LC_NUMERIC=fr_CH.UTF-8
LC_MONETARY=fr_CH.UTF-8
LC_PAPER=fr_CH.UTF-8
LC_MEASUREMENT=fr_CH.UTF-8
EOF

# --- Dotfiles du bureau pour les comptes futurs (/etc/skel) -----------------
if [ -d /opt/ubunturiri/desktop/skel ]; then
  cp -a /opt/ubunturiri/desktop/skel/. /etc/skel/
fi
# Propagation aux comptes DÉJÀ créés (ubun) : subiquity a peuplé son home
# depuis /etc/skel AVANT ce stade, sans nos dotfiles — mêmes pièges que
# fedoriri (test n°3). Pas de SELinux ici : pas de restorecon nécessaire.
for home in /home/*; do
  [ -d "$home" ] || continue
  u="$(basename "$home")"
  id "$u" >/dev/null 2>&1 || continue
  cp -a /etc/skel/. "$home/"
  chown -R "$u:$(id -gn "$u")" "$home"
done

# --- Scripts, thèmes et templates au niveau système --------------------------
find /opt/ubunturiri/scripts -name '*.sh' -exec chmod 0755 {} +
install -m 0755 /opt/ubunturiri/scripts/ubunturiri-theme-set   /usr/local/bin/ 2>/dev/null || true
install -m 0755 /opt/ubunturiri/scripts/render-theme.py        /usr/local/bin/ubunturiri-render-theme 2>/dev/null || true
mkdir -p /usr/share/ubunturiri
if [ -d /opt/ubunturiri/desktop/themes ]; then
  cp -a /opt/ubunturiri/desktop/themes    /usr/share/ubunturiri/themes
fi
if [ -d /opt/ubunturiri/desktop/templates ]; then
  cp -a /opt/ubunturiri/desktop/templates /usr/share/ubunturiri/templates
fi

# --- Session Xorg par défaut : Citrix exige X11 ------------------------------
# GDM3 : WaylandEnable=false force la session « Ubuntu on Xorg » sans rien
# demander à l'utilisateur. C'est LE point d'écart avec fedoriri (Wayland
# + xwayland-satellite + inhibiteurs de raccourcis) : ici X11 est natif.
if [ -f /etc/gdm3/custom.conf ]; then
  if grep -qE '^#?WaylandEnable=' /etc/gdm3/custom.conf; then
    sed -i 's/^#*WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
  else
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
  fi
  log "GDM : WaylandEnable=false (session Xorg par défaut) ✔"
fi

# --- Service de premier démarrage -------------------------------------------
install -m 0644 /opt/ubunturiri/systemd/ubunturiri-first-boot.service /etc/systemd/system/
systemctl enable ubunturiri-first-boot.service

log "chroot terminé : payload en place, Xorg forcé, first-boot armé"
