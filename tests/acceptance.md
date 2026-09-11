# tests/acceptance.md — procédures de vérification ubunturiri

Chaque test est rejouable ; aucun « ça devrait marcher » sans scénario.
Non exécutés ici (pas de VM Ubuntu ni de matériel dans l'environnement de dev).

## 1. Build et garde-fous

1. `bash tests/run-local-checks.sh` **sans** avoir lancé `set-secrets.sh` →
   doit échouer sur les placeholders.
2. `./iso/set-secrets.sh` (mdp user + phrase LUKS) → « Secrets en place ».
3. `bash tests/run-local-checks.sh` → « Tous les garde-fous passent. »
4. `sudo ./iso/build-iso.sh` → ISO produite + `.sha256`, message « vérifiée
   (GPG + sha256) ✔ » sur l'ISO amont.
   - Test négatif : corrompre 1 octet de l'ISO amont → le build doit échouer
     au `sha256sum -c`.

## 2. Boot et installation non interactive (VM)

1. Proxmox/virt-manager : VM UEFI, 1 disque ≥ 25 Go, CD-ROM = l'ISO, réseau.
2. Boot → l'installeur NE pose AUCUNE question (timeout 3 s puis déroule).
3. Observer tty1 : « disque cible : /dev/… (effacement TOTAL, LUKS2) »,
   « autoinstall généré — démarrage de subiquity ».
4. Fin : redémarrage automatique (média éjecté).

## 3. Chiffrement et authentification au boot

1. Au premier boot post-installation : subiquity/GDM demande la phrase LUKS.
2. `cryptsetup luksDump /dev/<part-luks>` → LUKS2, le keyslot 0 actif.
3. **La phrase n'est PAS lisible ailleurs** :
   `grep -r <phrase> /var/log/installer/` ne doit rien remonter ;
   `ls -l /tmp/luks-passphrase` ne doit PAS exister après installation.

## 4. Session Xorg (Citrix)

1. Login GDM : la session par défaut est « Ubuntu (Xorg) » —
   `echo $XDG_SESSION_TYPE` dans la session → `x11`.
2. `loginctl show-session $(loginctl | grep ubun | awk '{print $1}') -p Type` → `Type=x11`.
3. GDM : `grep WaylandEnable /etc/gdm3/custom.conf` → `WaylandEnable=false`.

## 5. Pop Shell et bureau

1. Extensions : `gnome-extensions list-user` inclut `pop-shell@system76.com`.
2. Tiling actif : Super+G bascule le mode tuilage ; les fenêtres se tuilent.
3. Thème par défaut : `cat ~/.config/ubunturiri/current-theme` →
   `tokyo-night` ; alacritty aux couleurs du thème.

## 6. Citrix Workspace app

1. `dpkg-query -W icaclient` → version installée (ligne stable).
2. `/opt/Citrix/ICAClient/util/ctx_rehash` a été exécuté (journal first-boot).
3. Connexion à un store Citrix réel (Swisscom) : lancement d'une appli HDX.
4. Multi-moniteur et redirection presse-papiers : à valider (limites citées
   dans les docs Citrix pour Workspace Linux).

## 7. Navigateur et outils

1. Brave : `dpkg-query -W brave-browser` → installé ; lanceur présent ;
   navigateur par défaut (`xdg-settings get default-web-browser`).
2. Claude Desktop : `dpkg-query -W claude-desktop`.
3. starship : `starship --version` (prompt actif dans bash).

## 8. Premier boot rejouable (idempotence)

1. `sudo /opt/ubunturiri/scripts/post-install.sh --dry-run` → affiche, ne
   fait rien.
2. `sudo rm /var/lib/ubunturiri/first-boot.done && sudo systemctl start
   ubunturiri-first-boot` → rejoue sans casser (témoin reposé).

## 9. Installation hors ligne (pool local)

1. Refaire le test 2 avec la VM **sans carte réseau** → installation complète
   grâce au pool (`/opt/ubunturiri-pool` source apt `file://`).
2. Le service de premier boot attend le réseau : sans réseau il échoue,
   laisse le témoin non posé, et retente au boot suivant (avec réseau).

## 10. Clé USB (média d'installation amovible)

1. Écrire l'ISO : `dd if=ubunturiri-….iso of=/dev/sdX bs=4M status=progress`.
2. Boot matériel : la seed est localisée malgré le label dupliqué
   (sda/sda1) — gen-autoinstall monte les partitions pour chercher
   `nocloud/user-hash.sh`, ne se fie pas au LABEL.
