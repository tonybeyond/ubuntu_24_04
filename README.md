# ubunturiri

ISO **Ubuntu 24.04 LTS** installable et entièrement automatisée : bureau
**GNOME + tiling GNOME** sur session **Xorg**, workflow et esthétique calqués
sur **Omarchy** (thèmes repris tels quels), avec **Citrix Workspace app**
comme prérequis dur. Portage Ubuntu de [fedoriri](https://github.com/tonybeyond/fedoriri)
— même architecture (secrets au build → autoinstall → premier boot), **sans
la partie Shadow.tech** (plus nécessaire).

```
ISO desktop Ubuntu vérifiée (GPG+sha256)
   └─ xorriso : injection seed NoCloud + pool local de .deb + autoinstall
        └─ installation sans réseau (LUKS2, clavier ch-fr, user ubun, GNOME)
             └─ 1er boot : ubunturiri-first-boot.service (console visible)
                  ├─ starship / paquets complémentaires
                  ├─ Citrix Workspace app (ligne stable .deb — Ubuntu supporté)
                  ├─ Brave (dépôt apt officiel)
                  ├─ Claude Desktop (AppImage communautaire)
                  └─ thème Omarchy par défaut (tokyo-night)
```

## Pourquoi Xorg et pas Wayland, tiling GNOME et pas Cosmic

Citrix Workspace app pour Linux exige **X11** (« Wayland isn't supported »,
docs Citrix v2601). D'où :

- **Cosmic : Wayland-only → éliminatoire.**
- **tiling GNOME : extension GNOME**, la session « Ubuntu on Xorg » est posée
  par défaut (`WaylandEnable=false` dans GDM) → X11 natif garanti, sans les
  workarounds Wayland de fedoriri (xwayland-satellite, inhibiteurs de
  raccourcis, fedoriri-passthrough).

C'est le portage le plus fidèle de l'esprit fedoriri tout en corrigeant son
point faible pour Citrix.

## Construction

Détails dans [iso/README.md](iso/README.md). Pas à pas :

**0. Où builder.** Sur une machine/VM **Ubuntu 24.04** (le pool apt exige un
hôte .deb). Prérequis :

```bash
sudo apt-get install -y curl gpg ca-certificates xorriso mtools isolinux dpkg-dev apt-utils rsync
# mksquashfs si on reconstruit des squashfs — pas requis ici (injection seule)
```

(Pas d'Ubuntu sous la main ? `./iso/build-iso.sh --podman` fait tout dans un
conteneur `ubuntu:24.04`.)

**1. Poser les deux secrets** (le build refuse tant que les placeholders
sont en place) :

```bash
./iso/set-secrets.sh
```

- **mot de passe de l'utilisateur `ubun`** → hash SHA-512 dans
  `iso/nocloud/user-hash.sh` (`openssl passwd -6`) ;
- **phrase LUKS** (demandée à chaque démarrage) → en clair dans
  `iso/nocloud/luks-passphrase.sh`, **fichier séparé** : subiquity recopie
  `user-data` dans `/var/log/installer/` du système installé — ces deux
  fichiers-là n'y transitent jamais, et la phrase est **effacée** (shred) à
  la fin de l'installation.

Ne commitez jamais ces fichiers remplis : `git restore iso/nocloud/user-hash.sh
iso/nocloud/luks-passphrase.sh`.

**2. Vérifier puis construire :**

```bash
bash tests/run-local-checks.sh
sudo ./iso/build-iso.sh
```

**3. Résultat :** `iso/build/ubunturiri-24.04.2-amd64.iso` (+ son `.sha256`).
Prévoir ~15 Go libres et une bonne connexion (ISO amont ~3 Go + pool).

Garde-fous intégrés — le build **échoue volontairement** si : placeholders
non remplacés ; signature GPG du fichier SHA256SUMS invalide ; sha256 de
l'ISO amont non concordant. L'ISO produite contient vos secrets : ne la
diffusez pas ; après installation, ajoutez une nouvelle phrase et retirez
celle de l'ISO : `cryptsetup luksChangeKey /dev/<partition-luks>`.

## Décisions structurantes

| Décision | Pourquoi |
|---|---|
| Voie NoCloud/autoinstall : ISO desktop amont + seed injectée au menu de boot | subiquity est l'installateur ; l'autoinstall est LE mécanisme officiel d'installation non interactive Ubuntu |
| Secrets dans des fichiers SÉPARÉS de `user-data` | subiquity recopie `user-data` dans `/var/log/installer/` : le hash et la phrase LUKS n'y finiraient sinon en clair |
| Génération de `/autoinstall.yaml` à l'installation (early-commands) | le disque cible est détecté (le plus gros, média exclu) ; la phrase LUKS ne vit que dans un keyfile temporaire effacé |
| **GNOME + tiling GNOME, Xorg forcé** (`WaylandEnable=false`) | Citrix exige X11 ; tiling GNOME garde un environnement GNOME familier avec le tiling |
| Citrix ligne **stable .deb** | Ubuntu 22/24.04 est supportée officiellement ; le paquet embarque webkit2gtk-4.0 → pas de mismatch, pas de `--nodeps` |
| Travail lourd au **premier boot**, pas dans late-commands | pas de réseau garanti en chroot, services non démarrables ; unité oneshot avec témoin, sortie console |
| Pool local de `.deb` sur l'ISO (source apt `file://`) | installation sans réseau ; dépendances résolues par apt en chroot de build |

## Arborescence

```
iso/
  set-secrets.sh           # mdp user (hash) + phrase LUKS, sans écho
  build-iso.sh             # télécharge/vérifie amont, pool, injection, ISO
  nocloud/
    user-data              # seed : ne fait QU'appeler gen-autoinstall.sh
    meta-data              # vide (seed NoCloud)
    gen-autoinstall.sh     # détecte le disque, lit les secrets, écrit /autoinstall.yaml
    user-hash.sh           # hash SHA-512 du mdp user (placeholder)
    luks-passphrase.sh     # phrase LUKS (placeholder)
    pool/                  # dépôt .deb local (rempli au build)
    payload/               # copié dans /opt/ubunturiri à l'installation
      scripts/
        lib/common.sh
        first-boot.sh  post-install.sh  late-chroot.sh
        install-citrix.sh  install-brave.sh  install-claude-desktop.sh
        ubunturiri-theme-set  render-theme.py
      systemd/ubunturiri-first-boot.service
      desktop/themes/       # 22 thèmes Omarchy (colors.toml)
      desktop/templates/    # alacritty, btop…
tests/run-local-checks.sh   # garde-fous pré-commit / pré-build
```

## Non vérifié ici

Pas de VM Ubuntu ni de matériel dans l'environnement de dev : l'installation
de bout en bout, l'affichage, le clavier. Chaque test prévu dans
[tests/acceptance.md](tests/acceptance.md). Les pièges documentés (clés USB
au label dupliqué, disque codé en dur, webkit2gtk) sont hérités des
apprentissages fedoriri.
