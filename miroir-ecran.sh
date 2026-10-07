#!/bin/bash
#
# Bascule d'affichage de l'écran externe USB/HDMI (adaptateur MacroSilicon
# MS91xx, pilote usbdisp).
#
# Usage : ./miroir-ecran.sh [etendu|miroir|arret]
#
#   etendu   deux bureaux distincts, l'écran USB à droite du portable
#   miroir   l'écran USB affiche exactement la même image (défaut)
#   arret    retour au portable seul, l'adaptateur reste branché
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ecran.sh"

MODE="${1:-miroir}"

if ! xrandr --query >/dev/null 2>&1; then
    echo "ERREUR: session X11 introuvable (xrandr a échoué)." >&2
    echo "       Ce pilote ne fonctionne pas sous Wayland : déconnecte-toi" >&2
    echo "       puis choisis « Xorg » ou « X11 » à l'écran de connexion." >&2
    exit 1
fi

# L'adaptateur se réénumère de temps en temps : sa sortie peut disparaître
# une fraction de seconde. On patiente 10 secondes avant d'abandonner.
attente=0
while true; do
    detecter_externe || true
    if [ -n "${EXTERNAL:-}" ] && xrandr --query | grep -qE "^${EXTERNAL} connected"; then
        break
    fi
    if [ "$attente" -ge 10 ]; then
        if lsusb | grep -qiE "345f:913[235]|534d:6021"; then
            echo "ERREUR: l'adaptateur est branché mais aucun écran n'apparaît." >&2
            echo "       Sa sortie HDMI ne lit aucun EDID : l'écran externe est" >&2
            echo "       éteint, sur une autre entrée, ou le câble n'est pas" >&2
            echo "       sur l'adaptateur. Allume-le puis relance." >&2
        else
            echo "ERREUR: l'adaptateur n'est pas détecté par le noyau." >&2
            echo "       Débranche le câble USB 10 secondes puis rebranche-le." >&2
        fi
        exit 1
    fi
    sleep 1
    attente=$((attente + 1))
done

# L'écran interne n'est utile que pour le miroir et le mode étendu.
if [ "$MODE" != "arret" ] && ! detecter_interne; then
    echo "ERREUR: impossible de repérer l'écran interne (eDP/LVDS/DSI)." >&2
    echo "       Liste tes écrans avec « xrandr --query » puis force le nom :" >&2
    echo "       USB_DISP_PRIMARY=\"eDP-1\" $0 $MODE" >&2
    exit 1
fi

case "$MODE" in
miroir)
    # Le miroir exige la même résolution et la même position sur les deux
    # écrans. Si l'écran externe ne connaît pas la résolution de la dalle
    # interne, on crée un mode compatible (via cvt) et on l'ajoute partout.
    calculer_mode_miroir
    appliquer_miroir
    echo "Miroir activé : $PRIMARY et $EXTERNAL affichent la même image en ${MIROIR_MODE}."
    ;;
etendu)
    xrandr --output "$EXTERNAL" --auto --right-of "$PRIMARY"
    echo "Mode étendu : $EXTERNAL est un deuxième bureau à droite de $PRIMARY."
    ;;
arret)
    xrandr --output "$EXTERNAL" --off
    echo "Écran externe désactivé. Seul l'écran du portable reste actif."
    ;;
*)
    echo "Usage: $0 [etendu|miroir|arret]" >&2
    exit 1
    ;;
esac

echo
filtre="^Screen"
if [ -n "${PRIMARY:-}" ]; then
    filtre="$filtre|^${PRIMARY}"
fi
xrandr --query | grep -E "$filtre|^${EXTERNAL}"
