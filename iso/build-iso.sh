#!/usr/bin/env bash
# build-iso.sh — construit l'ISO ubunturiri (Ubuntu 24.04 LTS, autoinstall).
#
# Principe (voie NoCloud/subiquity, l'équivalent Ubuntu de mkksiso+kickstart) :
#   1. télécharge l'ISO Ubuntu 24.04 Desktop officielle ;
#   2. VÉRIFIE SHA256SUMS (signature GPG Ubuntu) puis le sha256 de l'ISO —
#      échec du build si l'une des deux vérifications rate ;
#   3. constitue un pool local de .deb (dépendances incluses) copié sur l'ISO
#      pour une installation sans réseau ;
#   4. extrait l'ISO amont (xorriso), y copie nocloud/ + pool/, réécrit
#      grub.cfg et le menu BIOS (autoinstall 'ds=nocloud;s=/cdrom/nocloud/'),
#      puis recombine en ISO hybride + efiboot patchée.
#
# À lancer sur Ubuntu/Debian (ou : --podman pour s'auto-exécuter dans un
# conteneur ubuntu:24.04). Prérequis : curl gpg coreutils xorriso mtools
# isolinux (fichier isohdpfx.bin) apt ; le pool exige apt (hôte .deb).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../iso/nocloud/payload/scripts/lib/common.sh
source "$REPO_ROOT/iso/nocloud/payload/scripts/lib/common.sh"

ARCH=amd64
BASE_URL="https://releases.ubuntu.com/noble"
# La point-release (24.04.x) bouge : releases.ubuntu.com retire l'ancienne
# quand une nouvelle sort. On résout le nom d'ISO LE PLUS RÉCENT publié,
# jamais une version codée en dur (404 constaté le 2026-09 : 24.04.2 retirée).
ISO_FILE=""   # rempli par resolve_iso_name()
ISO_URL=""
ISO_SERIES="" # idem

BUILD_DIR="$SCRIPT_DIR/build"
OUT_ISO=""      # défaut posé dans resolve_iso_name (dépend de la série)
USE_PODMAN=0
SKIP_POOL=0
DRY_RUN=0
DRY_FLAG=()

usage() {
  cat <<EOF
Usage : $0 [options]
  --podman      s'exécute dans un conteneur ubuntu:24.04 (hôte non-Ubuntu)
  --skip-pool   ne pas (re)télécharger le pool de paquets (itérations rapides ;
                l'installation exigera alors le réseau)
  --pool-only   ne construit que le pool (pour cache), pas l'ISO
  --output F    chemin de l'ISO produite (défaut : build/ubunturiri-<serie>-amd64.iso)
  --dry-run     affiche les commandes sans les exécuter
  --help        cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --podman)    USE_PODMAN=1 ;;
    --skip-pool) SKIP_POOL=1 ;;
    --pool-only) POOL_ONLY=1 ;;
    --output)    shift; OUT_ISO="$1" ;;
    --dry-run)   DRY_RUN=1 ;;
    --help|-h)   usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
  shift
done
finalize_flags

# ---------------------------------------------------------------------------
# Garde-fous : refus de builder avec les placeholders des secrets.
# ---------------------------------------------------------------------------
check_placeholders() {
  local bad=0
  if grep -q 'CHANGEME_PASSWORD_HASH_SHA512' "$SCRIPT_DIR/nocloud/user-hash.sh"; then
    warn "le hash du mot de passe utilisateur n'a pas été remplacé — lancez ./iso/set-secrets.sh"
    bad=1
  fi
  if grep -q 'CHANGEME_LUKS_PASSPHRASE' "$SCRIPT_DIR/nocloud/luks-passphrase.sh"; then
    warn "la phrase de passe LUKS n'a pas été remplacée — lancez ./iso/set-secrets.sh"
    bad=1
  fi
  [ "$bad" -eq 0 ] || die "placeholders non remplacés — build refusé."
}

# ---------------------------------------------------------------------------
# Exécution en conteneur (hôte non-Ubuntu/Debian).
# ---------------------------------------------------------------------------
if [ "$USE_PODMAN" -eq 1 ]; then
  require_cmd podman
  log "relance dans un conteneur ubuntu:24.04…"
  exec podman run --rm -it --privileged \
    -v "$REPO_ROOT:/src:Z" -w /src \
    docker.io/library/ubuntu:24.04 \
    bash -c "apt-get update -qq && apt-get install -y --no-install-recommends \
               curl gpg ca-certificates xorriso mtools isolinux apt-utils dpkg-dev rsync \
             && ./iso/build-iso.sh $( [ "$SKIP_POOL" -eq 1 ] && printf -- '--skip-pool' )"
fi

# ---------------------------------------------------------------------------
# Prérequis : affiche ce qui manque et propose l'installation AVANT de mourir
# (sinon le script semble « ne rien faire » : premier require_cmd = die
# silencieux, aucun log émis auparavant).
# ---------------------------------------------------------------------------
ensure_prereqs() {
  local pkgs=(curl gpg coreutils xorriso mtools isolinux dpkg-dev apt-utils rsync ca-certificates ubuntu-keyring)
  local cmds=(curl gpg sha256sum xorriso mcopy mtype dpkg-scanpackages rsync apt-get)
  local missing=() c
  for c in "${cmds[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Outils manquants : ${missing[*]}" >&2
    echo "Installez les prérequis :" >&2
    echo "  sudo apt-get update && sudo apt-get install -y ${pkgs[*]}" >&2
    if [ "$(id -u)" -eq 0 ] && [ -t 0 ]; then
      read -r -p "Les installer maintenant ? [O/n] " rep
      if [ "${rep:-O}" != "n" ] && [ "${rep:-O}" != "N" ]; then
        apt-get update -qq && apt-get install -y "${pkgs[@]}" || die "installation des prérequis échouée"
        # Re-vérification après installation.
        for c in "${cmds[@]}"; do
          command -v "$c" >/dev/null 2>&1 || die "toujours absent après installation : $c"
        done
        return
      fi
    fi
    exit 1
  fi
}
ensure_prereqs
check_placeholders
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# Résolution du nom d'ISO amont : point-release la plus récente publiée.
# ---------------------------------------------------------------------------
resolve_iso_name() {
  log "résolution de l'ISO amont (point-release courante 24.04)…"
  ISO_FILE="$(curl -fsSL "$BASE_URL/" \
    | grep -oE "ubuntu-24\.04\.[0-9]+-desktop-${ARCH}\.iso" \
    | sort -uV | tail -1)"
  [ -n "$ISO_FILE" ] || die "aucune ISO desktop ${ARCH} trouvée sur $BASE_URL"
  ISO_SERIES="$(grep -oE '24\.04\.[0-9]+' <<<"$ISO_FILE")"
  ISO_URL="${BASE_URL}/${ISO_FILE}"
  # OUT_ISO dépend de la série résolue, sauf si --output a été passé.
  [ -z "$OUT_ISO" ] && OUT_ISO="$BUILD_DIR/ubunturiri-${ISO_SERIES}-${ARCH}.iso"
  log "ISO amont : $ISO_FILE → $OUT_ISO"
}

# ---------------------------------------------------------------------------
# 1+2. ISO amont : téléchargement, vérification GPG + sha256.
# ---------------------------------------------------------------------------
fetch_and_verify_upstream() {
  resolve_iso_name
  UPSTREAM_ISO="$(cd "$BUILD_DIR" && pwd)/$ISO_FILE"
  if [ ! -f "$UPSTREAM_ISO" ]; then
    log "téléchargement de l'ISO amont ($ISO_FILE, ~3 Go)…"
    run curl -fL --retry 3 -o "$UPSTREAM_ISO.part" "$ISO_URL"
    run mv "$UPSTREAM_ISO.part" "$UPSTREAM_ISO"
  else
    log "ISO déjà présente, vérification seulement"
  fi
  run curl -fsSL -o "$BUILD_DIR/SHA256SUMS" "$BASE_URL/SHA256SUMS"
  run curl -fsSL -o "$BUILD_DIR/SHA256SUMS.gpg" "$BASE_URL/SHA256SUMS.gpg"

  if [ "$DRY_RUN" -eq 0 ]; then
    local gnupg_tmp
    gnupg_tmp="$(mktemp -d)"; chmod 700 "$gnupg_tmp"
    # Clés du CD image team Ubuntu (vérification du fichier de sommes).
    gpg --homedir "$gnupg_tmp" --keyserver hkps://keyserver.ubuntu.com \
        --recv-keys 843938DF228D22F7B3742BC0D94AA3F0EFE21092 \
      || die "import de la clé Ubuntu impossible — build interrompu"
    gpg --homedir "$gnupg_tmp" --verify "$BUILD_DIR/SHA256SUMS.gpg" "$BUILD_DIR/SHA256SUMS" \
      || die "signature GPG de SHA256SUMS invalide — build interrompu"
    rm -rf "$gnupg_tmp"
    # Vérifie la ligne exacte du fichier ISO (format « hash *nom » du SUMS) :
    # nom en ancre, un seul résultat attendu, puis sha256sum -c depuis le
    # répertoire de l'ISO (le SUMS utilise des chemins relatifs « *nom »).
    local sumline
    sumline="$(grep -E "^[0-9a-f]{64} \*${ISO_FILE}\$" "$BUILD_DIR/SHA256SUMS")" \
      || die "aucune ligne de checksum pour $ISO_FILE dans SHA256SUMS"
    [ "$(wc -l <<<"$sumline" | tr -d ' ')" = "1" ] \
      || die "plusieurs lignes de checksum pour $ISO_FILE — inattendu"
    ( cd "$BUILD_DIR" && printf '%s\n' "$sumline" | sha256sum -c - ) \
      || die "sha256 de l'ISO invalide — build interrompu"
    log "ISO amont vérifiée (GPG + sha256) ✔"
  fi
}

# ---------------------------------------------------------------------------
# 3. Pool local de .deb : le bureau + dépendances, pour installer sans réseau.
# ---------------------------------------------------------------------------
build_package_pool() {
  local pool="$SCRIPT_DIR/nocloud/pool"
  mkdir -p "$pool"
  if [ "$SKIP_POOL" -eq 1 ]; then
    warn "pool sauté (--skip-pool) : l'installation exigera le réseau"
    return
  fi
  # Paquets explicites (mêmes noms que la section packages de gen-autoinstall).
  # NOTE : Pop Shell n'a JAMAIS été publié dans noble (jammy seulement ;
  # l'upstream 1.2.0 date de 2021, incompatible GNOME 46). On installe donc
  # gnome-shell-extension-ubuntu-tiling-assistant (tiling, MAINTENU noble) ;
  # install-pop-shell.sh tentera le vrai Pop Shell en overlay au 1er boot.
  local pkgs="ubuntu-desktop-minimal gnome-shell-extension-ubuntu-tiling-assistant \
    gnome-shell-extension-manager gnome-tweaks alacritty network-manager \
    openssh-server curl ca-certificates"
  log "téléchargement du pool de paquets ($(echo $pkgs | wc -w | tr -d ' ') paquets explicites + dépendances)…"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] apt-get --download-only ... $pkgs"
    return
  fi
  [ "$(id -u)" -eq 0 ] || die "cette étape exige root : relancez avec sudo ./iso/build-iso.sh"
  # Cache apt DÉDIÉ (aucun partage avec l'hôte). Le piège du run n°2 : un
  # cache custom vide n'hérite NI des listes NI des sources de l'hôte → apt ne
  # voyait aucun paquet. On pointe donc update ET download sur ce cache, avec
  # les sources Ubuntu EXPLICITES (noble main+universe : Pop Shell et
  # alacritty sont dans universe, pas main).
  local aptc="$BUILD_DIR/apt-cache" srclist="$BUILD_DIR/ubuntu-pool.list"
  mkdir -p "$aptc/archives/partial" "$aptc/lists/partial"
  apt_opts=(
    -o Dir::Cache="$aptc"
    -o Dir::Cache::archives="$aptc/archives"
    -o Dir::State::lists="$aptc/lists"
    -o APT::Sandbox::User=root
    -o Debug::NoLocking=1
    -o Dir::Etc::sourcelist="$srclist"
    -o Dir::Etc::sourceparts=-
    -o APT::Get::List-Cleanup=0
  )
  # Le piège du run n°3 : rediriger Dir::Etc::sourcelist DÉSACTIVE le keyring
  # par défaut → apt ne vérifie plus les InRelease (« Missing key 91BC93C »,
  # repo « not signed »). On force donc le keyring officiel dans chaque ligne
  # (signed-by) ET on s'assure qu'il est présent (ubuntu-keyring).
  local keyring="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
  [ -f "$keyring" ] || apt-get install -y ubuntu-keyring || die "ubuntu-keyring absent (requis pour la vérif GPG du pool)"
  cat > "$srclist" <<EOF
deb [signed-by=$keyring] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [signed-by=$keyring] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [signed-by=$keyring] http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOF
  log "apt update (sources Ubuntu explicites, cache dédié)…"
  apt-get "${apt_opts[@]}" update -qq \
    || die "apt update a échoué (accès à archive.ubuntu.com / security.ubuntu.com ?)"
  # --download-only : ferme la résolution complète et dépose les .deb.
  apt-get "${apt_opts[@]}" install -y --download-only --no-install-recommends \
    $pkgs \
    || die "téléchargement du pool échoué — un paquet est-il absent de noble ?"
  mkdir -p "$pool"
  find "$aptc/archives" -name '*.deb' -not -path '*partial*' -exec cp -f {} "$pool/" \;
  [ -n "$(find "$pool" -name '*.deb' | head -1)" ] \
    || die "aucun .deb récupéré depuis $aptc/archives — chemin de cache inattendu ?"
  # Index du dépôt local (Packages.gz) : late-chroot.sh l'utilise comme
  # source apt file:// à l'installation.
  ( cd "$pool" && dpkg-scanpackages -m . /dev/null 2>/dev/null | gzip -9c > Packages.gz ) \
    || die "dpkg-scanpackages a échoué (apt-utils installé ?)"
  log "pool local prêt : $(find "$pool" -name '*.deb' | wc -l | tr -d ' ') .deb"
}

# ---------------------------------------------------------------------------
# 4+5. Extraction, injection seed + payload + pool, réécriture du boot.
# ---------------------------------------------------------------------------
assemble_iso() {
  # L'extraction a besoin de l'ISO amont (déjà vérifiée) : la résolution doit
  # avoir eu lieu — fetch_and_verify_upstream est appelé avant assemble_iso.
  [ -n "$ISO_FILE" ] || die "ISO amont non résolue (resolve_iso_name pas appelé ?)"
  UPSTREAM_ISO="$(cd "$BUILD_DIR" && pwd)/$ISO_FILE"
  [ -f "$UPSTREAM_ISO" ] || die "ISO amont absente : $UPSTREAM_ISO"
  local extract="$BUILD_DIR/extract"
  run rm -rf "$extract"
  mkdir -p "$extract"
  log "extraction de l'ISO amont…"
  xorriso -osirrox on -indev "$UPSTREAM_ISO" -extract / "$extract" >/dev/null 2>&1 \
    || die "extraction osirrox échouée — xorriso >= 1.4 requis"

  # Seed NoCloud + payload + pool à la racine de l'ISO.
  run rsync -a --delete \
      --exclude 'user-hash.sh' --exclude 'luks-passphrase.sh' \
      "$SCRIPT_DIR/nocloud/" "$extract/nocloud-public/"
  # Les secrets eux-mêmes (chmod 600 sur l'ISO) + le reste de la seed.
  run rsync -a "$SCRIPT_DIR/nocloud/user-hash.sh" "$SCRIPT_DIR/nocloud/luks-passphrase.sh" "$extract/nocloud-public/"
  # gen-autoinstall lit /cdrom/nocloud : on pose le vrai dossier attendu.
  run mv "$extract/nocloud-public" "$extract/nocloud"
  [ -f "$extract/nocloud/meta-data" ] || : > "$extract/nocloud/meta-data"

  # --- Réécriture du menu EFI (grub.cfg du système de fichiers ISO) --------
  local grub="$extract/boot/grub/grub.cfg"
  [ -f "$grub" ] || die "boot/grub/grub.cfg introuvable dans l'ISO extraite"
  chmod u+w "$grub"
  # Remplace les entrées « Try or Install » par une entrée autoinstall unique.
  cat > "$grub" <<'GRUB'
set timeout=3
menuentry "ubunturiri — installation automatique (Ubuntu 24.04)" {
  set gfxpayload=keep
  linux /casper/vmlinuz autoinstall 'ds=nocloud;s=/cdrom/nocloud/' quiet ---
  initrd /casper/initrd
}
GRUB

  # --- Menu BIOS (isolinux/txt.cfg ou boot/grub déjà couvert) --------------
  local iso_linux="$extract/isolinux/txt.cfg"
  if [ -f "$iso_linux" ]; then
    chmod u+w "$iso_linux"
    cat > "$iso_linux" <<'ISOLINUX'
default install
label install
  menu label ^ubunturiri — installation automatique
  kernel /casper/vmlinuz
  append initrd=/casper/initrd autoinstall ds=nocloud;s=/cdrom/nocloud/ quiet ---
ISOLINUX
  fi

  # --- Recombinaison hybride (BIOS + UEFI) ---------------------------------
  # Recette EXACTE des outils Ubuntu (isohdimage) pour une ISO noble :
  # on n'essaie PAS de deviner/parsing le catalogue El Torito de l'amont
  # (approche du début, fragile : le '-V 'Ubuntu…'' était rejeté comme
  # « Unrecognized option »). Ubuntu noble boote :
  #   - BIOS : isolinux/isolinux.bin
  #   - UEFI : boot/grub/efi.img (image El Torito), + --efi-boot en GPT hybride
  #   - MBR hybride : /usr/lib/ISOLINUX/isohdpfx.bin (paquet isolinux)
  run rm -f "$OUT_ISO"
  local efi_img=""
  for cand in "$extract/boot/grub/efi.img" "$extract/EFI/boot/efi.img" "$extract/efi.img"; do
    [ -f "$cand" ] && { efi_img="${cand#$extract/}"; break; }
  done
  [ -n "$efi_img" ] || die "image efi.img introuvable dans l'arborescence extraite (boot/grub/efi.img attendu)"

  local isohdpfx="/usr/lib/ISOLINUX/isohdpfx.bin"
  [ -f "$isohdpfx" ] || isohdpfx="/usr/lib/syslinux/isohdpfx.bin"
  [ -f "$isohdpfx" ] || die "isohdpfx.bin introuvable (installez le paquet isolinux)"

  xorriso -as mkisofs \
    -r -V "UBUNTURIRI" \
    -o "$OUT_ISO" \
    -iso-level 3 -full-iso9660-filenames \
    -J -l \
    -isohybrid-mbr "$isohdpfx" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
      -e "$efi_img" \
      -no-emul-boot \
      -isohybrid-gpt-basdat \
    "$extract" \
    || die "xorriso as mkisofs a échoué"

  if [ "$DRY_RUN" -eq 0 ]; then
    ( cd "$(dirname "$OUT_ISO")" && sha256sum "$(basename "$OUT_ISO")" | tee "$(basename "$OUT_ISO").sha256" )
  fi
  log "ISO produite : $OUT_ISO"
}

fetch_and_verify_upstream
build_package_pool
[ "${POOL_ONLY:-0}" -eq 1 ] && { log "pool prêt (--pool-only), arrêt ici"; exit 0; }
assemble_iso
