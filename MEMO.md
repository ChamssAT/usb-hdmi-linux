# MÉMO — Adaptateur USB/HDMI sur Parrot OS

> Mémo de travail pour reprendre le sujet sans tout redécouvrir.
> Dernière mise à jour : 26/09/2026 — **fonctionnel**.

---

## 0. POINT DE REPRISE — en attente de redémarrage

Pause demandée le 26/09/2026 après une coupure de courant, pour ne pas
interrompre la session opencode. Rien n'est cassé, rien n'est à réinstaller.

**Ce que le redémarrage va régler tout seul :**
- `dkms.conf` contient `AUTOINSTALL="yes"` → `usbdisp_drm` et `usbdisp_usb`
  se rechargent automatiquement au boot. **Ne pas relancer le script
  d'installation.**

**Ce qui est à faire une fois la session revenue (30 secondes) :**

```bash
# 1. rebrancher l'adaptateur (il n'était plus détecté après la coupure)
#    -> les modules étant déjà chargés, card1 doit réapparaître seul

# 2. vérifier
lsusb | grep -iE "345f|534d"
ls /dev/dri/                     # card0 + card1 attendus
xrandr --query | grep HDMI-1-1   # doit dire "connected 1920x1080"

# 3. choisir le mode voulu
~/Bureau/usb-display/miroir-ecran.sh miroir    # ou : etendu
```

**Si `HDMI-1-1` reste `disconnected` alors que `lsusb` et `card1` sont là** :
problème physique. Vérifier que l'écran est allumé et que le câble HDMI est
sur le port de l'adaptateur (et pas sur le portable).

**Si l'adaptateur est absent de `lsusb` et ne revient pas** : firmware
verrouillé → débrancher le câble USB **et** toute autre alimentation pendant
2 minutes, puis reconnecter (voir §6).

---

## 1. En une phrase

Adaptateur USB→HDMI **sans pilote Linux fourni** → identification de la puce
(MacroSilicon **MS9132**) → compilation du pilote DRM **GPL-2.0** en portage
communautaire → installation **DKMS** → carte graphique `card1` ajoutée →
écran externe utilisable en mode **étendu** ou **dupliqué (miroir)**.

---

## 2. Environnement (à ne pas rediagnostiquer)

| Élément | Valeur |
|---|---|
| Adaptateur | `345f:9132` — « USB Display usb extscreen » |
| Puce | **MacroSilicon MS9132** (famille MS91xx), **sortie** vidéo |
| Preuve | Signature de l'exe : `Copyright © MacroSilicon 2022` |
| Mode liaison | **480 Mb/s** (USB 2.0) — bus `003`, contrôleur `xhci_hcd` |
| Système | Parrot Security 7.3 (echo), Debian 13 |
| Noyau | `7.0.13+parrot7-amd64` |
| GPU | Intel 2nd gen Core iGPU (`i915`) → `card0` |
| Session | **X11 / MATE** (donc `xrandr`, pas de Wayland) |
| Prereqs | `dkms` 3.2.2, `build-essential`, `gcc` 14.2, headers 7.0.13 : **déjà là** |

Sortie X11 de l'écran externe : **`HDMI-1-1`** (les `-2` et `-3` sont
déconnectées, c'est un hub HDMI). Sortie interne : **`LVDS-1`**.

---

## 3. Décisions prises et pourquoi

1. **Pas d'evdi/DisplayLink** — ne pilote que les puces DisplayLink. ID de
   module différent : ça ne marchera jamais.
2. **Pas le pilote officiel tel quel** — le code source constructeur
   (V3.0.3.13) vise le noyau 6.1 et compile jusqu'à ~6.6. Or on est en **7.0**.
   Correctifs bloquants : `FOP_UNSIGNED_OFFSET`, `drm_do_get_edid()` supprimé,
   `struct_mutex` retiré de `struct drm_device`, `platform_driver.remove`
   Returning `void`, `timer_container_of()`.
3. **Oui `bambinounos/ms91xx-linux-drm`** — même code GPL constructeur, patché
   jusqu'à 7.0+, packagé DKMS. La logique protocolaire USB est intacte.
4. **Build de test avant tout sudo** — compile dans le dossier de travail,
   réversible par définition. A confirmé la compatibilité 7.0 avant d'écrire
   dans `/usr/src`.
5. **Mode miroir via CVT** — voir §5, point clé.
6. **Sélecteur graphique en plus de la CLI** — demandé explicitement.

---

## 4. État vérifié (constat réel, pas supposé)

- `dkms status` → **`msdisp/3.0.3.13, 7.0.13+parrot7-amd64, installed`**
- `/sys/module` → `usbdisp_usb` + `usbdisp_drm` chargés
- `/dev/dri/` → `card0` (i915) **+ `card1`** (adaptateur)
- `xrandr --query` → `HDMI-1-1 connected 1920x1080` en mode **étendu**
  (`Screen 0: 3520 x 1080`)
- Les deux bascules `miroir` ↔ `etendu` ont été **testées et re-testées**, stables

---

## 5. Point technique à ne pas oublier : le problème EDID

**1600×900 (résolution native de la dalle) est ABSENT de l'EDID du moniteur
externe.** Un miroir exige mode identique + position identique sur les deux
sorties, donc `--same-as` seul ne peut pas cloner en 1600×900.

Solution retenue : déclarer le mode en CVT.

```bash
xrandr --newmode "1600x900c" 118.25 1600 1688 1856 2112 900 903 908 934 -hsync +vsync
xrandr --addmode LVDS-1 1600x900c
xrandr --addmode HDMI-1-1 1600x900c
xrandr --output LVDS-1 --primary --mode 1600x900c --pos 0x0 \
       --output HDMI-1-1 --mode 1600x900c --pos 0x0
```

`1600x900c` est **le seul mode de qualité native valide sur les deux sorties**
(la dalle et un écran fixe 16:9). Repli si le moniteur le refuse : `1280x800`.

⚠️ Le mode CVT est **volatile** : disparu à chaque redémarrage. C'est le
section à relancer, d'où l'installeur autostart.

---

## 6. Pièges rencontrés (coûteux, ne pas les rejouer)

| Piège | Symptôme | Contournement retenu |
|---|---|---|
| **Écran éteint / débranché** | `HDMI-1-1 disconnected`, EDID 0 octet, les deux bascules échouent **sans message** | `miroir-ecran.sh` teste `lsusb` pour distinguer « adaptateur absent » de « pas d'écran détecté » et l'explique. Vérifier : `cat /sys/class/drm/card1-HDMI-A-1/status` et `wc -c < .../edid` |
| **Réénumération de l'adaptateur** | `HDMI-1-1` disparaît de `xrandr` pendant ~1 s → la bascule échouait 1 fois sur 2 | `miroir-ecran.sh` boucle 10× avec `sleep 1` avant d'abandonner |
| **Coupure de courant** (26/09/2026) | Adaptateur disparu de `lsusb`, écran éteint, mode d'affichage perdu | Les modules **restent chargés** : rebrancher suffit, `card1` revient tout seul. Ne pas réinstaller le pilote. |
| **`rmmod usbdisp_drm`** | use-after-free constructeur → oops noyau, refcount −1, module bloqué | **Interdit.** Recharger = redémarrer |
| Mode CVT non persisté | Le miroir disparaît au reboot | `~/.config/autostart/` (user-level, pas de sudo) |
| Lien 480 Mb/s | Miroir saccadé (framebuffer complet envoyé à chaque changement) | Port USB 3.0 bleu si l'appareil le propose |
| Renumérotation `534d:6021` | L'ID USB change après branchement | **Normal**, le pilote gère les deux |
| Dalle rouge, aucun événement | Firmware verrouillé | Débrancher ~2 min, toutes alimentations coupées |
| Noms de modules | `modprobe` → `usbdisp_usb`, mais `lsusb -t` affiche `Driver=msdisp_usb` | Ce n'est pas un bug : module ≠ nom de pilote USB. Ne pas « corriger » |

> **Distinction importante** : `disconnected` sur le connecteur HDMI ne veut
> **pas** dire que le pilote est cassé. Ça veut seulement dire « aucun écran
> détecté ». Les deux modules chargés + `card1` présent + EDID à 0 octet =
> problème physique, pas logiciel.

---

## 7. Commandes de référence

```bash
# bascule d'affichage (instantané, sans sudo)
~/Bureau/usb-display/miroir-ecran.sh {miroir|etendu|arret}
~/Bureau/usb-display/choisir-mode-ecran.sh          # sélecteur graphique (zenity)

# diagnostic
lsusb | grep -iE "345f|534d"
lsusb -t | grep -B2 Driver=msdisp_usb
xrandr --query
ls -la /dev/dri/
lsmod | grep -E '^usbdisp'
dkms status | grep msdisp

# désinstallation complète
sudo dkms remove msdisp/3.0.3.13 --all && sudo reboot
```

---

## 8. Reste à faire (rien d'obligatoire)

- [ ] **Tester le port USB 3.0 bleu** → vérifier `lsusb -t` passe à `5000M`.
      Gain attendu surtout en miroir. Non testé : l'appareil est sur 480M.
- [ ] **Activer la persistance du miroir au démarrage** (une ligne) :
      ```bash
      mkdir -p ~/.config/autostart
      cp ~/Bureau/usb-display/miroir-ecran.sh ~/.config/autostart/
      ~/.config/autostart/miroir-ecran.sh miroir
      ```
      **Pas fait volontairement** : cela figerait le mode *miroir* à chaque
      session. À ne faire que si le miroir est le mode souhaité par défaut.
- [ ] Si besoin d'un mode commun plus universel : tester `1280x800` sur le
      moniteur externe (dégradation de la dalle du portable).

---

## 9. Inventaire

| Chemin | Rôle |
|---|---|
| `~/Bureau/usb-display/Adaptateur_USB_HDMI_sous_Linux_Parrot_OS.pdf` | Doc 12 pages (fpdf2) |
| `~/Bureau/usb-display/installer-msdisp.sh` | Installation DKMS idempotente |
| `~/Bureau/usb-display/miroir-ecran.sh` | Bascule étendu / miroir / arrêt |
| `~/Bureau/usb-display/choisir-mode-ecran.sh` | Sélecteur graphique zenity |
| `~/Bureau/usb-display/ms91xx-linux-drm/` | Code source du pilote (dépôt Git) |
| `/usr/src/msdisp-3.0.3.13/` | Sources installées par DKMS |
| `/lib/modules/7.0.13+parrot7-amd64/updates/dkms/` | `usbdisp_drm.ko.xz`, `usbdisp_usb.ko.xz` |
| `~/.local/share/applications/ecran-usb-hdmi.desktop` | Raccourci menu MATE |
| `/tmp/opencode/gen_pdf.py` | Générateur PDF (**volatile**, à recopier si régénéré) |
| `/tmp/opencode/accents.py` | Passe d'accentuation du générateur (**volatile**) |

---

## 10. Note sur la chaîne de production du PDF

Si le PDF doit être régénéré, `/tmp` sera vidé : **recopier d'abord
`gen_pdf.py` et `accents.py` ailleurs.**

Deux pièges déjà payés dans cette chaîne, à ne pas réintroduire :

1. `accents.py` **ne doit toucher que les littéraux de chaîne**, sinon il
   accentue le code Python lui-même (`enumerate` → `énuméré`). D'où l'usage de
   `tokenize` + repérage des positions.
2. Les blocs `pdf.code([...])` sont masqués **par correspondance complète**
   (`finditer` + `group(0)`) et les clés de masquage sont **indexées paddées**
   (`__CB0007__`) — sinon `__CB7__` matcherait dans `__CB70__` et détruirait
   le fichier. La liste `LITERALS` protège `miroir-ecran.sh`, les arguments
   `etendu`/`arret` et `video 226` : sans elle, l'accentuation casse le script.

Le script **valide** ces points à chaque exécution et sort en erreur si un
littéral est altéré. Ne pas supprimer ces vérifications.
