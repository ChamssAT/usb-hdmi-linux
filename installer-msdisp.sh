#!/bin/bash
#
# Installation du pilote DRM MacroSilicon MS9132 (USB -> HDMI) via DKMS
# pour l'adaptateur lsusb 345f:9132
#
# Prerequis deja verifies : dkms, build-essential, linux-headers-$(uname -r)
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ms91xx-linux-drm"
DST="/usr/src/msdisp-3.0.3.13"
PKG="msdisp"
VER="3.0.3.13"

if [ ! -d "$SRC" ]; then
    echo "ERREUR: sources introuvables dans $SRC" >&2
    exit 1
fi

echo "==> Verification des prerequis"
if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
    echo "ERREUR: headers du noyau manquants pour $(uname -r)" >&2
    echo "       installez: sudo apt install linux-headers-\$(uname -r)" >&2
    exit 1
fi
command -v dkms    >/dev/null || { echo "ERREUR: dkms absent"      >&2; exit 1; }
command -v rsync   >/dev/null || { echo "ERREUR: rsync absent"     >&2; exit 1; }
command -v make    >/dev/null || { echo "ERREUR: make absent"      >&2; exit 1; }
echo "    kernel  : $(uname -r)"
echo "    dkms    : $(dkms --version)"
echo "    headers : OK"

echo
echo "==> Copie des sources vers $DST"
sudo mkdir -p "$DST"
sudo rsync -a --delete --exclude .git --exclude '*.o' --exclude '*.ko' \
    --exclude '.*.cmd' --exclude '*.mod*' --exclude 'Module.symvers' \
    --exclude 'modules.order' "$SRC/" "$DST/"
echo "    OK"

echo
echo "==> Nettoyage d'une installation DKMS precedente (si presente)"
if dkms status "$PKG/$VER" >/dev/null 2>&1; then
    sudo dkms remove "$PKG/$VER" --all || true
fi

echo
echo "==> dkms add"
sudo dkms add "$PKG/$VER"

echo
echo "==> dkms build   (C'EST L'ETAPE CRITIQUE)"
if ! sudo dkms build "$PKG/$VER"; then
    echo
    echo "############################################################" >&2
    echo "### ECHEC DE LA COMPILATION                              ###" >&2
    echo "############################################################" >&2
    echo "Log complet :" >&2
    echo "  sudo less /var/lib/dkms/msdisp/$VER/build/make.log" >&2
    echo "  (ou: sudo tail -50 /var/lib/dkms/msdisp/$VER/build/make.log)" >&2
    exit 2
fi

echo
echo "==> dkms install"
sudo dkms install "$PKG/$VER"

echo
echo "==> Chargement immediat des modules"
sudo depmod -a
sudo modprobe usbdisp_usb || echo "    (avertissement: usbdisp_usb non charge)"
sudo modprobe usbdisp_drm || echo "    (avertissement: usbdisp_drm non charge)"

echo
echo "==> Etat"
echo "--- modules charges ---"
lsmod | grep usbdisp || echo "    aucun module usbdisp charge"
echo "--- /dev/dri ---"
ls -la /dev/dri/
echo "--- usb ---"
lsusb | grep -iE "345f|534d" || echo "    adaptateur non detecte"
lsusb -t | grep -A2 -iE "345f|534d" || true

echo
echo "############################################################"
echo "# Installation terminee.                               #"
echo "#                                                       #"
echo "# Si /dev/dri/ contient card1 en plus de card0 :        #"
echo "#   -> l'adaptateur est reconnu,Reconnectez l'ecran      #"
echo "#      puis configurez-le:                               #"
echo "#        xrandr --query                                   #"
echo "#        xrandr --output <SORTIE> --auto --right-of eDP1 #"
echo "#                                                       #"
echo "# Si rien n'a change : debranchez/rebranchez l'adaptateur #"
echo "# ou redemarrez.                                        #"
echo "#                                                       #"
echo "# NE JAMAIS faire: sudo rmmod usbdisp_drm (bug kernel)   #"
echo "# Pour recharger le pilote -> redemarrer.                #"
echo "############################################################"
