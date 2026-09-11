# iso/README.md — construction de l'ISO ubunturiri

## Prérequis (hôte Ubuntu/Debian)

```bash
sudo apt-get install -y curl gpg ca-certificates xorriso mtools isolinux dpkg-dev apt-utils rsync
```

- `xorriso` : extraction (`osirrox`) et recombinaison (`as mkisofs`) de l'ISO ;
- `isolinux` : boot BIOS hybride (isohdpfx.bin lu depuis l'ISO amont) ;
- `dpkg-dev` : `dpkg-scanpackages` pour l'index `Packages.gz` du pool local ;
- `apt-utils` : dépendances du pool.

`./iso/build-iso.sh --podman` s'exécute dans un conteneur `ubuntu:24.04`
(hôte non-Ubuntu) — `--privileged` requis (montages apt).

## Étapes du build (`build-iso.sh`)

1. **Télécharge** `ubuntu-24.04.2-desktop-amd64.iso` depuis releases.ubuntu.com.
2. **Vérifie** GPG (`SHA256SUMS.gpg` + clé CD image team `843938DF…`) puis le
   sha256 de l'ISO — échec du build sinon.
3. **Pool local** : `apt-get --download-only` des paquets de la section
   `packages:` (bureau minimal, Pop Shell, alacritty…) + fermeture de
   dépendances, copiés dans `nocloud/pool/` + `Packages.gz`. C'est une source
   apt `file://` permanente dans la cible → installation **sans réseau**.
4. **Injection** : extraction `osirrox`, copie de `nocloud/` (seed), écriture
   d'un `grub.cfg` EFI et d'un `txt.cfg` BIOS uniques :
   ```
   linux /casper/vmlinuz autoinstall 'ds=nocloud;s=/cdrom/nocloud/' quiet ---
   ```
5. **Recombinaison** `xorriso as mkisofs` : les options El Torito amont sont
   **relues du catalogue de l'ISO** (`-report_el_torito as_mkisofs`) et
   rejouées telles quelles — jamais de valeur codée en dur pour les images de
   boot (BIOS/EFI), qui varient d'une point-release à l'autre.

## Secrets

Voir la [README racine](../README.md#1-poser-les-deux-secrets). Points clés :

- `user-hash.sh` et `luks-passphrase.sh` sont **séparés de `user-data`** :
  subiquity recopie ce dernier dans `/var/log/installer/` du système installé.
- La phrase LUKS n'existe que dans `/tmp/luks-passphrase` (keyfile curtin,
  root:root 0400) pendant l'installation, puis `shred -u` en late-commands.
- Garde-fou : placeholders non remplacés → build refusé.

## Alternatives écartées

| Voie | Pourquoi non |
|---|---|
| Cubic (chroot GUI) | inter-actif, difficilement rejouable en CI/script |
| live-build from scratch | lourd à maintenir ; l'installateur Desktop gère mieux LUKS+autoinstall |
| Ubuntu Server + `tasksel ubuntu-desktop` | produit presque identique à Desktop minimal, en plus fragile |
| kickstart/kickseed | Debian-specific, pas supporté par subiquity depuis 20.04 |

## Test de l'ISO

VM (Proxmox/virt-manager) : ajoutez l'ISO comme CD-ROM, bootez dessus. Le
système s'installe seul, redémarre, et le service de premier boot déroule
Citrix/Brave/thèmes sur la console. Matériel réel : écrivez l'ISO avec
`dd` ou Ventoy — la détection de la seed ne dépend pas du label de volume
(clé USB au label dupliqué : le seed est localisé en montant les partitions,
constaté dans fedoriri).
