#!/bin/bash
#
# Maintien du mode d'affichage pour l'adaptateur USB/HDMI MS91xx.
#
# POURQUOI CE SCRIPT EXISTE :
# l'adaptateur coupe puis rétablit sa liaison HDMI interne toutes les
# ~15 secondes. À chaque rétablissement, le serveur X recalcule la
# configuration et impose le mode préféré de l'EDID du moniteur (souvent
# 1920x1080), en écrasant le mode choisi. Conséquence : seul le mode
# natif survit ; miroir, étendu et arrêt retombent après une dizaine
# de secondes.
#
# Ce script observe la configuration en continu et la réapplique dès
# qu'elle dévie.
#
# Usage :
#   ./maintien-mode.sh demarrer [miroir|etendu|arret]
#   ./maintien-mode.sh arreter
#   ./maintien-mode.sh etat
#
# Note : tant qu'il tourne, il défend LE mode demandé au démarrage.
# Une bascule manuelle via miroir-ecran.sh sera donc annulée à la
# prochaine vérification — arrêtez d'abord le maintien.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ecran.sh"

INTERVALE=2
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/maintien-ecran.pid"
SIGFILE="${XDG_RUNTIME_DIR:-/tmp}/maintien-ecran.sig"
LOGFILE="${XDG_CACHE_HOME:-$HOME/.cache}/maintien-ecran.log"
APPLY="$DIR/miroir-ecran.sh"

# Empreinte de la configuration actuelle : "taille_ecran|mode_interne|mode_externe"
signature() {
    xrandr --query 2>/dev/null | awk -v p="${PRIMARY:-}" -v e="${EXTERNAL:-}" '
        function geom(line,   i, n, f) {
            n = split(line, f, " ")
            if (f[2] != "connected") return "disc"
            for (i = 3; i <= n; i++) {
                if (f[i] == "off") return "off"
                if (f[i] ~ /^[0-9]+x[0-9]+\+/) return f[i]
            }
            return "aucun"
        }
        $1 == "Screen" {
            for (i = 1; i <= NF; i++)
                if ($i == "current") scr = $(i + 1) "x" $(i + 3)
        }
        p != "" && $1 == p { pr = geom($0) }
        e != "" && $1 == e { ex = geom($0) }
        END { gsub(/[^0-9x]/, "", scr); print scr "|" pr "|" ex }'
}

# La configuration est-elle encore celle qu'on veut défendre ?
conforme() {
    [ -f "$SIGFILE" ] || return 1
    [ "$(signature)" = "$(cat "$SIGFILE")" ]
}

en_cours() {
    [ -f "$PIDFILE" ] || return 1
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

arreter() {
    if en_cours; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        echo "Maintien arrêté (pid $(cat "$PIDFILE"))."
    else
        echo "Aucun maintien en cours."
    fi
    rm -f "$PIDFILE" "$SIGFILE"
}

etat() {
    detecter_externe || true
    detecter_interne || true
    if en_cours; then
        echo "Maintien ACTIF (pid $(cat "$PIDFILE"))."
        echo "Configuration actuelle : $(signature)"
        tail -3 "$LOGFILE" 2>/dev/null
    else
        echo "Maintien inactif."
        echo "Configuration actuelle : $(signature)"
    fi
}

demarrer() {
    local mode="${1:-miroir}"
    case "$mode" in
        miroir|etendu|arret) ;;
        *) echo "Usage: $0 demarrer [miroir|etendu|arret]" >&2; exit 1 ;;
    esac

    if en_cours; then
        # Déjà actif : on change simplement de mode.
        kill "$(cat "$PIDFILE")" 2>/dev/null
        sleep 1
    fi

    if ! detecter_externe; then
        echo "AVERTISSEMENT: aucune sortie d'adaptateur détectée pour l'instant." >&2
        echo "               Le maintien démarrera quand vous le brancherez." >&2
    fi

    mkdir -p "$(dirname "$LOGFILE")"
    : > "$LOGFILE"
    rm -f "$SIGFILE"

    (
        trap 'rm -f "$PIDFILE" "$SIGFILE"; exit 0' TERM INT
        # BASHPID, pas $$ : dans un sous-shell $$ désigne encore le parent,
        # et le fichier PID serait alors invalide dès la fin du script.
        echo "$BASHPID" > "$PIDFILE"
        echo "$(date '+%H:%M:%S') maintien $mode démarré" >> "$LOGFILE"

        while true; do
            # L'adaptateur peut se débrancher : on attend sereinement.
            detecter_externe || { sleep "$INTERVALE"; continue; }
            if [ "$mode" != "arret" ]; then
                detecter_interne || { sleep "$INTERVALE"; continue; }
            fi

            if ! conforme; then
                if xrandr --query 2>/dev/null | grep -qE "^${EXTERNAL} connected"; then
                    if "$APPLY" "$mode" >> "$LOGFILE" 2>&1; then
                        sleep 1
                        signature > "$SIGFILE"
                        echo "$(date '+%H:%M:%S') mode $mode réappliqué" >> "$LOGFILE"
                    fi
                fi
            fi
            sleep "$INTERVALE"
        done
    ) </dev/null >>"$LOGFILE" 2>&1 &
    disown
    sleep 1
    echo "Maintien du mode « $mode » actif (contrôle toutes les ${INTERVALE}s)."
    echo "Journal : $LOGFILE"
}

case "${1:-etat}" in
    demarrer) shift; demarrer "${1:-miroir}" ;;
    arreter)  arreter ;;
    etat)     etat ;;
    *) echo "Usage: $0 {demarrer [miroir|etendu|arret]|arreter|etat}" >&2; exit 1 ;;
esac
