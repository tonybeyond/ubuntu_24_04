# ubunturiri — ISO Ubuntu 24.04 LTS automatisée, GNOME + Pop Shell, X11
ISO_NAME := ubunturiri
RELEASE  := 24.04
ARCH     := amd64
BUILD    := iso/build
ISO      := $(BUILD)/$(ISO_NAME)-$(RELEASE)-$(ARCH).iso

.PHONY: secrets check build pool iso clean

## secrets : remplit les deux secrets (mdp utilisateur + phrase LUKS)
secrets:
	./iso/set-secrets.sh

## check : garde-fous (placeholders, syntaxe shell)
check:
	bash tests/run-local-checks.sh

## build : tout (vérification + ISO + sha256). Exige root/sudo.
build: check
	sudo ./iso/build-iso.sh

## pool : (re)télécharge uniquement le pool local de paquets (cache apt)
pool:
	sudo ./iso/build-iso.sh --pool-only

clean:
	sudo rm -rf $(BUILD)
