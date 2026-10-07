#!/bin/bash
#
# Fonctions communes aux scripts d'affichage de l'adaptateur USB/HDMI.
#
# Ce fichier ne s'exécute pas tout seul : il est chargé par
# miroir-ecran.sh, maintien-mode.sh et choisir-mode-ecran.sh.
#
# La détection est automatique. Si elle se trompe chez toi (plusieurs écrans,
# noms de sorties inhabituels), force les valeurs avec ces variables :
#
#   export USB_DISP_PRIMARY="eDP-1"      # écran interne du portable
#   export USB_DISP_EXTERNAL="HDMI-1-1"  # sortie de l'adaptateur USB
#   export USB_DISP_MIROIR="1600x900"    # résolution imposée en mode miroir
#
# Voir les noms réels de tes écrans avec : xrandr --query

xrandr_out() { xrandr --query 2>/dev/null; }

# Première sortie connectée dont le nom commence par le motif $1,
# en ignorant éventuellement la sortie $2.
sortie_connectee() {
    xrandr_out | awk -v pat="$1" -v skip="${2:-}" \
        '$1 ~ pat && $2 == "connected" && $1 != skip { print $1; exit }'
}

# Remplit EXTERNAL : la sortie de l'adaptateur USB (HDMI, DisplayPort ou DVI).
detecter_externe() {
    if [ -n "${USB_DISP_EXTERNAL:-}" ]; then
        EXTERNAL="$USB_DISP_EXTERNAL"
    else
        EXTERNAL="$(sortie_connectee '^(HDMI|DP|DVI)-')"
    fi
    [ -n "$EXTERNAL" ]
}

# Remplit PRIMARY : l'écran interne (eDP, LVDS ou DSI selon l'âge du portable).
detecter_interne() {
    if [ -n "${USB_DISP_PRIMARY:-}" ]; then
        PRIMARY="$USB_DISP_PRIMARY"
    else
        PRIMARY="$(sortie_connectee '^(eDP|LVDS|DSI)-' "${EXTERNAL:-}")"
    fi
    # Repli : tout écran connecté qui n'est pas l'adaptateur
    if [ -z "$PRIMARY" ]; then
        PRIMARY="$(sortie_connectee '^' "${EXTERNAL:-}")"
    fi
    [ -n "$PRIMARY" ]
}

# Géométrie actuelle d'une sortie : "1600x900+0+0", "off", "aucun" ou "disc".
geometrie() {
    xrandr_out | awk -v o="$1" '
        function geom(line,   i, n, f) {
            n = split(line, f, " ")
            if (f[2] != "connected") return "disc"
            for (i = 3; i <= n; i++) {
                if (f[i] == "off") return "off"
                if (f[i] ~ /^[0-9]+x[0-9]+\+/) return f[i]
            }
            return "aucun"
        }
        $1 == o { print geom($0); exit }'
}

# Résolution affichée actuellement par une sortie (ex. "1600x900").
resolution_courante() {
    xrandr_out | awk -v o="$1" '$1 == o && $2 == "connected" {
        for (i = 1; i <= NF; i++)
            if ($i ~ /^[0-9]+x[0-9]+\+/) { sub(/\+.*/, "", $i); print $i; exit }
    }'
}

# Vrai si la sortie $1 connaît déjà le mode $2 (dans sa liste de modes).
sortie_conna_mode() {
    xrandr_out | awk -v o="$1" -v m="$2" '
        $1 == o { suite = 1; next }
        suite && substr($0, 1, 1) !~ /[[:space:]]/ { suite = 0 }
        suite && $1 == m { vu = 1 }
        END { exit !vu }'
}

# Calcule la résolution à imposer en mode miroir :
#   1. la résolution de l'écran interne si l'écran externe la propose déjà ;
#   2. sinon un mode fabriqué sur mesure (cvt), ajouté aux deux écrans.
# Renseigne MIROIR_MODE ("1600x900"), MIROIR_MODE_NAME et MIROIR_MODELINE.
calculer_mode_miroir() {
    MIROIR_MODE="${USB_DISP_MIROIR:-$(resolution_courante "$PRIMARY")}"
    if [ -z "$MIROIR_MODE" ]; then
        echo "ERREUR: impossible de connaître la résolution de l'écran (${PRIMARY:-inconnu})." >&2
        echo "       Forcez-la, par exemple : USB_DISP_MIROIR=1920x1080 $0 miroir" >&2
        return 1
    fi

    if sortie_conna_mode "$EXTERNAL" "$MIROIR_MODE"; then
        MIROIR_MODE_NAME="$MIROIR_MODE"
        MIROIR_MODELINE=""
        return 0
    fi

    local w h genere=""
    w="${MIROIR_MODE%x*}"
    h="${MIROIR_MODE#*x}"
    if command -v cvt >/dev/null 2>&1; then
        genere="$(cvt "$w" "$h" 60 2>/dev/null |
            awk '/^Modeline/ { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }')"
    fi
    if [ -z "$genere" ] && [ "$MIROIR_MODE" = "1600x900" ]; then
        # Repli : la modeline du portable de référence, même sans cvt
        genere="118.25 1600 1688 1856 2112 900 903 908 934 -hsync +vsync"
    fi
    if [ -z "$genere" ]; then
        echo "ERREUR: ${EXTERNAL} ne propose pas ${MIROIR_MODE} et 'cvt' est introuvable." >&2
        echo "       Installez cvt (paquet xserver-xorg-core) ou imposez une résolution" >&2
        echo "       que connaît l'écran externe :" >&2
        echo "         USB_DISP_MIROIR=1920x1080 $0 miroir" >&2
        return 1
    fi
    MIROIR_MODE_NAME="${MIROIR_MODE}c"
    MIROIR_MODELINE="$genere"
}

# Applique le mode miroir : crée le mode sur mesure si besoin, puis cale les
# deux écrans sur la même résolution, à la même position (0,0).
appliquer_miroir() {
    if [ -n "$MIROIR_MODELINE" ]; then
        # shellcheck disable=SC2086  # la modeline est faite d'arguments séparés
        xrandr --newmode "$MIROIR_MODE_NAME" $MIROIR_MODELINE 2>/dev/null || true
        xrandr --addmode "$PRIMARY"  "$MIROIR_MODE_NAME" 2>/dev/null || true
        xrandr --addmode "$EXTERNAL" "$MIROIR_MODE_NAME" 2>/dev/null || true
    fi
    xrandr --output "$PRIMARY"  --primary --mode "$MIROIR_MODE_NAME" --pos 0x0 \
           --output "$EXTERNAL" --mode "$MIROIR_MODE_NAME" --pos 0x0
}

# Mode actuellement en vigueur : miroir, etendu, arret ou inconnu.
etat_courant() {
    if ! detecter_externe || ! xrandr --query | grep -qE "^${EXTERNAL} connected"; then
        echo "inconnu"
        return 0
    fi
    local g_ext g_int
    g_ext="$(geometrie "$EXTERNAL")"
    if [ "$g_ext" = "off" ]; then
        echo "arret"
        return 0
    fi
    if ! detecter_interne; then
        echo "etendu"
        return 0
    fi
    g_int="$(geometrie "$PRIMARY")"
    if [ "$g_ext" = "$g_int" ] && [ "$g_ext" != "aucun" ]; then
        echo "miroir"
    else
        echo "etendu"
    fi
}
