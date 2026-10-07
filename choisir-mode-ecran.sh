#!/bin/bash
#
# Sélecteur graphique : choisir le mode d'affichage de l'écran externe
# USB/HDMI (adaptateur MacroSilicon MS91xx).
#
#   etendu  : deux bureaux distincts, l'écran USB à droite du portable
#   miroir  : l'écran USB affiche la même image que le portable
#   arret   : l'écran USB est éteint, l'adaptateur reste branché
#
# Utilisable comme lanceur de menu ou depuis le bureau.
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ecran.sh"
SCRIPT="$DIR/miroir-ecran.sh"

if ! command -v zenity >/dev/null 2>&1; then
    echo "zenity est requis pour l'interface graphique." >&2
    echo "Installez-le (paquet zenity) ou utilisez directement :" >&2
    echo "  $SCRIPT {etendu|miroir|arret}" >&2
    exec "$SCRIPT" miroir
fi

courant="$(etat_courant)"

choix=$(zenity --list --title="Écran externe USB/HDMI" \
    --width=460 --height=290 \
    --text="Mode d'affichage actuel : <b>$courant</b>\n\nChoisissez le mode à appliquer :" \
    --column="Mode" --column="Description" --hide-column=1 --print-column=1 \
    --ok-label="Appliquer" --cancel-label="Annuler" \
    "etendu"  "Deux écrans séparés : navigation libre entre les deux (recommandé)" \
    "miroir"  "L'écran USB affiche exactement la même image que le portable" \
    "arret"   "Éteint l'écran externe sans débrancher l'adaptateur" 2>/dev/null) || exit 0

[ -n "$choix" ] || exit 0
"$SCRIPT" "$choix"
