# Adaptateur USB → HDMI sous Linux (MacroSilicon MS91xx)

Vous avez acheté un petit adaptateur USB vers HDMI sur AliExpress, Amazon ou
ailleurs. Sous Windows, il suffit d'installer le `.exe` du fabricant. Sous
Linux… rien ne se passe. Pas d'écran, parfois pas même de signal.

Le problème vient du matériel : ces adaptateurs embarquent une puce
**MacroSilicon MS91xx**, et le fabricant **ne fournit aucun pilote Linux**.
Ce dépôt comble le manque avec deux morceaux :

- **le pilote** (`ms91xx-linux-drm/`) : le code source officiel GPL de
  MacroSilicon, corrigé pour compiler sur les noyaux modernes (6.x et 7.x) et
  emballé pour DKMS. Il s'installe une fois pour toutes et survit aux mises à
  jour du noyau ;
- **quelques scripts** qui gèrent ce qui se passe *après* : passer en mode
  étendu ou miroir, et surtout empêcher l'adaptateur de tout remettre à zéro
  toutes les 15 secondes (oui, il fait ça — voir plus bas).

> **Testé sur** : Parrot OS 7.3 (noyau 7.0, session X11/MATE) avec un
> adaptateur MS9132, et d'après le dépôt du pilote sur Ubuntu 24.04
> (noyau 6.17). Si ça ne marche pas chez vous, la section
> [Dépannage](#dépannage) existe pour ça.

## Mon adaptateur est concerné ?

Branchez-le, puis :

```bash
lsusb | grep -iE "345f|534d"
```

| ID USB | Nom affiché | Verdict |
|---|---|---|
| `345f:9132`, `345f:9133`, `345f:9135` | « MS USB Video » | ✅ oui |
| `534d:6021` | « MacroSilicon USB Video » | ✅ oui — c'est le même adaptateur, juste renommé après branchement |


Pour les adaptateurs **USB → VGA** (puce MS912C), ça marche aussi, mais il faut
deux options de module supplémentaires : tout est expliqué dans
[docs/MS912C-VGA.md](docs/MS912C-VGA.md).

## Ce qu'il y a dans ce dépôt

| Fichier | À quoi ça sert |
|---|---|
| `installer-msdisp.sh` | Installe le pilote via DKMS (une seule fois, avec sudo) |
| `miroir-ecran.sh` | Bascule entre les modes : `etendu`, `miroir`, `arret` |
| `choisir-mode-ecran.sh` | La même chose, mais dans une fenêtre à cliquer |
| `maintien-mode.sh` | Garde le mode choisi malgré l'adaptateur (voir plus bas) |
| `lib-ecran.sh` | Fonctions communes : détection des écrans, calcul des modes |
| `ms91xx-linux-drm/` | Le pilote lui-même (sources, Makefile, DKMS) |
| `ecran-usb-hdmi.desktop` | Raccourci de menu pour le sélecteur graphique |
| `MEMO.md` | Notes de travail détaillées (dépannage, historique) |
| `Adaptateur_USB_HDMI_sous_Linux_Parrot_OS.pdf` | Documentation d'origine, 12 pages |
| `WinUSBDisplay_…exe`, `UsbDisplay_…dmg` | Installateurs Windows/macOS du constructeur — inutiles sous Linux, gardés par référence |

## Prérequis

Debian / Ubuntu / Parrot OS :

```bash
sudo apt install dkms build-essential linux-headers-$(uname -r) x11-xserver-utils
# optionnel, pour le sélecteur graphique :
sudo apt install zenity
```

Fedora : `sudo dnf install dkms kernel-devel xorg-x11-server-utils`
Arch : `sudo pacman -S dkms linux-headers xorg-xrandr`

Deux conditions à respecter :

1. **Une session X11.** Le pilote pilote l'affichage via `xrandr`, qui ne sait
   rien faire sous Wayland. Sous GNOME : menu de session (engrenage) →
   « GNOME sur Xorg ». Si l'écran externe n'apparaît pas, c'est presque
   toujours ça.
2. **Une carte graphique capable de « rediffuser » son image** (Source
   Output). Dans la grande majorité des cas c'est le cas ; vérification en une
   commande :

```bash
xrandr --listproviders
# le « provider 0 » doit mentionner Source Output dans ses capacités
```

## Installation

```bash
git clone https://github.com/ChamssAT/usb-hdmi-linux.git
cd usb-hdmi-linux
./installer-msdisp.sh
```

L'installeur fait tout dans l'ordre : vérifie les dépendances, copie les sources
dans `/usr/src`, compile via DKMS (l'étape critique), charge les modules. Il est
idempotent — le relancer ne casse rien.

À la fin, vous devez voir à peu près ceci :

```
--- modules charges ---
usbdisp_usb               45056  0
usbdisp_drm               61440  1 usbdisp_usb
--- /dev/dri ---
card0   <- votre carte graphique habituelle
card1   <- l'adaptateur USB    ← c'est ça, le succès
```

Si la compilation échoue, le log complet est ici :

```bash
sudo tail -50 /var/lib/dkms/msdisp/3.0.3.13/build/make.log
```

**Ensuite** : débranchez l'adaptateur 10 secondes puis rebranchez-le (si `card1`
n'apparaît pas), connectez l'écran HDMI, et vérifiez :

```bash
xrandr --query | grep HDMI    # doit dire « connected »
```

## Utilisation au quotidien

Trois modes, un seul script :

```bash
./miroir-ecran.sh etendu    # deux bureaux séparés (recommandé)
./miroir-ecran.sh miroir    # l'écran USB duplique l'écran du portable
./miroir-ecran.sh arret     # écran USB éteint, sans débrancher
```

Si vous préférez cliquer que taper :

```bash
./choisir-mode-ecran.sh
```

Ça ouvre une petite fenêtre Zenity avec les trois choix et le mode actuel en
gras. Pour en faire un vrai lanceur de menu, copiez `ecran-usb-hdmi.desktop`
dans `~/.local/share/applications/` (et ajustez le chemin dans le fichier si
vous avez cloné le dépôt ailleurs).

### Le point qui piège tout le monde : le maintien du mode

L'adaptateur MS91xx coupe puis rétablit sa liaison HDMI interne toutes les
~15 secondes. À chaque rétablissement, X11 recalcule la configuration et
**remet le mode préféré de l'EDID de l'écran** (souvent 1920×1080), en écrasant
votre choix. Sans remède, vous passez en miroir… et dix secondes plus tard vous
êtes revenu en étendu.

```bash
./maintien-mode.sh demarrer miroir   # ou etendu / arret
./maintien-mode.sh etat              # état courant
./maintien-mode.sh arreter           # on arrête de surveiller
```

Le script compare la configuration réelle à la configuration voulue toutes les
2 secondes et la réapplique dès qu'elle dévie. Rien d'exotique : il rappelle
simplement `miroir-ecran.sh`, c'est tout.

> Tant qu'il tourne, il défend **le mode demandé au démarrage**. Si vous
> basculez à la main pendant ce temps, votre bascule sera annulée à la
> prochaine vérification — arrêtez d'abord le maintien.

Bonne nouvelle pour la suite : `dkms.conf` contient `AUTOINSTALL="yes"`, donc
les modules se recompilent et se rechargent tout seuls après une mise à jour du
noyau. Inutile de relancer l'installateur.

## Personnaliser chez vous

Les scripts détectent les écrans automatiquement — dalle interne
(`eDP`/`LVDS`/`DSI`) et sortie de l'adaptateur (`HDMI`/`DP`/`DVI`). Si la
détection se trompe (plusieurs écrans branchés, noms inhabituels), tout se force
par variable d'environnement :

```bash
export USB_DISP_PRIMARY="eDP-1"      # votre écran interne
export USB_DISP_EXTERNAL="HDMI-1-1"  # la sortie de l'adaptateur
export USB_DISP_MIROIR="1600x900"    # résolution imposée en mode miroir
```

Pour connaître les vrais noms chez vous : `xrandr --query`.

### La résolution en mode miroir

Un miroir parfait exige la **même** résolution des deux côtés. Il arrive que
votre écran externe ne connaisse pas la résolution native de la dalle du
portable (fréquent : dalle en 1600×900, moniteur qui ne propose que du
1920×1080 et du 1280×720). Le script fabrique alors le mode manquant avec
`cvt` et l'ajoute aux deux écrans — rien à faire de votre côté.

Si ça coince quand même, imposez une résolution que les deux connaissent :

```bash
USB_DISP_MIROIR=1280x800 ./miroir-ecran.sh miroir
```

## Démarrage automatique

- **Les modules** : déjà gérés par DKMS (`AUTOINSTALL="yes"`), rien à faire.
- **Le mode d'affichage** : à vous, via l'autostart de votre bureau :

```bash
mkdir -p ~/.config/autostart
cp ecran-usb-hdmi.desktop ~/.config/autostart/
```

Conseil : ne figez le miroir en autostart que si c'est vraiment le mode que
vous voulez à chaque connexion.

## Dépannage

Commandes de diagnostic, dans l'ordre :

```bash
lsusb | grep -iE "345f|534d"                # l'adaptateur est-il vu ?
ls /dev/dri/                                # card0 + card1 attendus
lsmod | grep usbdisp                        # modules chargés ?
dkms status | grep msdisp                   # DKMS dit "installed" ?
xrandr --query                              # "connected" ?
cat /sys/class/drm/card1-HDMI-A-1/status    # connected / disconnected
wc -c < /sys/class/drm/card1-HDMI-A-1/edid  # 0 octet = aucun écran de branché
```

| Symptôme | Ce que ça veut dire | Ce qu'il faut faire |
|---|---|---|
| `disconnected` alors que `card1` est bien là | **Pas** un problème de pilote : aucun écran n'est détecté | Écran éteint, mauvaise entrée HDMI, ou câble branché sur le portable au lieu de l'adaptateur |
| L'adaptateur disparaît de `lsusb` | Firmware dans un état coincé | Débranchez le câble USB **et** toute alimentation pendant 2 minutes, puis rebranchez |
| L'adaptateur est vu mais `xrandr` ne le voit pas pendant ~1 s | Réénumération normale | `miroir-ecran.sh` gère déjà ce cas (10 essais) ; relancez simplement |
| Vous avez fait `sudo rmmod usbdisp_drm` | Bug connu du pilote : use-after-free | **Ne jamais le faire.** Seul un redémarrage débloque la situation |
| Image saccadée en miroir | Le lien tourne en USB 2.0 (480 Mb/s) | Branchez sur un port **USB 3.0** (bleu) et vérifiez via `lsusb -t` que le débit affiche `5000M` |
| `lsmod` dit `usbdisp_usb` mais `lsusb -t` affiche `Driver=msdisp_usb` | Ce n'est pas un bug : nom de module ≠ nom de pilote USB | Ne « corrigez » rien |
| `HDMI-1-1` disparaît de `xrandr` dès que vous changez de mode | Réénumération de l'adaptateur | Relancez la commande ; ou laissez `maintien-mode.sh` faire le travail |

Après une coupure de courant ou un redémarrage : **pas de réinstallation**. Les
modules sont toujours là, rebranchez l'adaptateur et `card1` revient tout seul.

Rien à voir avec votre cas ? `MEMO.md` contient les notes complètes, et
`docs/MS912C-VGA.md` traite les adaptateurs VGA.

## Désinstallation

```bash
sudo dkms remove msdisp/3.0.3.13 --all
sudo reboot
```

## Limites connues

- Fonctionne **sous X11** ; sous Wayland pur, la sortie peut ne pas apparaître
  (basculez en Xorg à l'écran de connexion).
- Le mode miroir en USB 2.0 reste perfectible : tout le framebuffer est
  renvoyé à chaque changement d'image — d'où l'intérêt du port USB 3.0.
- Testé à la maison sur une puce Intel ; le support AMD est passé par des
  contributions externes (voir l'historique du dépôt pilote).

## Licence et crédits

- Le pilote `ms91xx-linux-drm/` est du code source **officiel MacroSilicon**
  publié sous **GPL-2.0**, corrigé et emballé DKMS pour les noyaux modernes.
  Son histoire est suivie ici :
  [bambinounos/ms91xx-linux-drm](https://github.com/bambinounos/ms91xx-linux-drm).
- Les scripts de ce dépôt sont également sous **GPL-2.0** (voir `LICENSE`).
- Merci aux contributeurs du dépôt pilote (support amdgpu, correctifs de
  robustesse).

---

**En résumé** : `lsusb` confirme votre adaptateur → `./installer-msdisp.sh` →
`./miroir-ecran.sh etendu` → `./maintien-mode.sh demarrer etendu` → profitez de
votre deuxième écran.
