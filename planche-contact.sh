#!/usr/bin/env bash
# planche-contact.sh — génère une planche contact (damier de captures) pour
# chaque vidéo du dossier courant et de ses sous-dossiers.
#
# Prérequis (macOS) :  brew install ffmpeg
# Utilisation       :  cd /dossier/de/videos && planche-contact.sh [options]
#                      planche-contact.sh -h   pour la liste des options
#
# Compatible avec bash 3.2 (celui de macOS).

set -u

CONF_FILE="${PLANCHE_CONF:-$HOME/.planche-contact.conf}"

# ---------------------------------------------------------------- paramètres
NB_CAPTURES=12          # nombre de captures par vidéo
COLONNES=4              # nombre de colonnes du damier
LARGEUR_VIGNETTE=480    # largeur de chaque capture (px)
MARGE_INTERNE=6         # marge entre les images (px)
MARGE_EXTERNE=6         # marge autour du damier (px)
COULEUR_FOND="black"    # couleur de fond / des marges (nom ffmpeg ou 0xRRGGBB)
FORMAT="jpg"            # jpg ou png
QUALITE=95              # qualité JPEG en % (1 à 100)
PREFIXE="planche_"      # texte ajouté AVANT le nom de la vidéo
SUFFIXE=""              # texte ajouté APRÈS le nom de la vidéo (avant l'extension)
EXTENSIONS="mp4 mov mkv avi m4v wmv flv webm mpg mpeg mts m2ts ts"
DOSSIER_SORTIE=""       # vide = à côté de la vidéo ; sinon chemin
ECRASER="non"           # oui / non : remplacer une planche déjà existante

# Description des réglages affichés dans le menu (tableaux parallèles).
# Types : int (min/max/pas), choice (liste fermée), choice+ (liste + saisie
# libre), text (saisie libre).
KEYS=(NB_CAPTURES COLONNES LARGEUR_VIGNETTE MARGE_INTERNE MARGE_EXTERNE
      COULEUR_FOND FORMAT QUALITE PREFIXE SUFFIXE EXTENSIONS DOSSIER_SORTIE ECRASER)
LABELS=("Nombre de captures" "Colonnes du damier" "Largeur d'une capture (px)"
        "Marge entre les images (px)" "Marge autour du damier (px)"
        "Couleur de fond" "Format de sortie" "Qualité JPEG (%)"
        "Préfixe du fichier" "Suffixe du fichier" "Extensions traitées" "Dossier de sortie"
        "Écraser l'existant")
TYPES=(int int int int int choice+ choice int text text text text choice)
MINS=(1 1 100 0 0 "" "" 1 "" "" "" "" "")
MAXS=(500 50 4000 200 200 "" "" 100 "" "" "" "" "")
STEPS=(1 1 20 1 1 "" "" 1 "" "" "" "" "")
CHOICES=("" "" "" "" "" "black white gray 0x202020 0xf0f0f0" "jpg png" "" "" "" "" "" "non oui")
HINTS=("Combien d'images extraites, réparties uniformément sur la vidéo."
       "Nombre d'images par ligne du damier."
       "Largeur de chaque vignette ; la hauteur suit le format de la vidéo."
       "Espace entre deux vignettes."
       "Espace entre le damier et le bord de l'image."
       "Couleur des marges : choisir avec ←/→ ou saisir (nom ffmpeg, 0xRRGGBB)."
       "jpg (léger) ou png (sans perte)."
       "100 = meilleure qualité, fichier plus lourd (jpg uniquement)."
       "Texte ajouté avant le nom de la vidéo (planche_plage.jpg). « - » pour aucun."
       "Texte ajouté après le nom, avant l'extension (plage_planche.jpg). « - » pour aucun."
       "Extensions séparées par des espaces."
       "Vide = à côté de chaque vidéo. « - » pour revenir à ce mode."
       "Régénérer les planches déjà présentes ?")

NB_KEYS=${#KEYS[@]}
MSG=""
ERR=""
KEY=""
NB_VIDEOS=0

# Valeurs par défaut conservées pour la touche « d » (réinitialiser).
for k in "${KEYS[@]}"; do printf -v "DEF_$k" '%s' "${!k}"; done

charger_conf() {
  # shellcheck disable=SC1090
  [ -f "$CONF_FILE" ] && . "$CONF_FILE"
}

sauver_conf() {
  {
    for k in "${KEYS[@]}"; do printf '%s=%q\n' "$k" "${!k}"; done
  } > "$CONF_FILE"
}

# ------------------------------------------------------------------- outils
verifier_outils() {
  local outil
  for outil in ffmpeg ffprobe; do
    if ! command -v "$outil" >/dev/null 2>&1; then
      echo "Erreur : '$outil' est introuvable. Installez-le avec :  brew install ffmpeg" >&2
      exit 1
    fi
  done
}

indice_de() { # indice_de CLE -> affiche l'indice dans KEYS
  local i
  for ((i = 0; i < NB_KEYS; i++)); do
    [ "${KEYS[$i]}" = "$1" ] && { echo "$i"; return 0; }
  done
  return 1
}

# valider INDICE VALEUR : renvoie 0 si valide, sinon 1 et le motif dans ERR
valider() {
  local i=$1 v=$2 c
  case "${TYPES[$i]}" in
    int)
      case "$v" in ''|*[!0-9]*) ERR="un nombre entier est attendu"; return 1 ;; esac
      if [ "${#v}" -gt 6 ] || [ "$v" -lt "${MINS[$i]}" ] || [ "$v" -gt "${MAXS[$i]}" ]; then
        ERR="valeur attendue entre ${MINS[$i]} et ${MAXS[$i]}"; return 1
      fi ;;
    choice)
      for c in ${CHOICES[$i]}; do [ "$c" = "$v" ] && return 0; done
      ERR="choix possibles : ${CHOICES[$i]}"; return 1 ;;
    choice+)
      [ -n "$v" ] || { ERR="la valeur ne peut pas être vide"; return 1; } ;;
    text)
      case "${KEYS[$i]}" in
        EXTENSIONS) [ -n "${v// /}" ] || { ERR="au moins une extension"; return 1; } ;;
        PREFIXE|SUFFIXE) case "$v" in */*) ERR="« / » interdit dans un préfixe ou un suffixe"; return 1 ;; esac ;;
      esac ;;
  esac
  return 0
}

# regler CLE VALEUR : applique une valeur validée (utilisé par les options)
regler() {
  local i
  i=$(indice_de "$1") || return 1
  if valider "$i" "$2"; then
    printf -v "$1" '%s' "$2"
  else
    echo "Option invalide pour ${LABELS[$i]} : $ERR" >&2
    exit 2
  fi
}

# ------------------------------------------------- recherche des vidéos
# Écrit sur stdout les chemins (séparés par NUL) des vidéos à traiter.
lister_videos() {
  local args=() ext premier=1 exclure=()
  for ext in $EXTENSIONS; do
    ext="${ext#.}"
    [ $premier -eq 0 ] && args+=(-o)
    args+=(-iname "*.${ext}")
    premier=0
  done
  [ $premier -eq 1 ] && return 0
  [ -n "$PREFIXE" ] && exclure=(! -name "${PREFIXE}*")
  find . -type f \( "${args[@]}" \) "${exclure[@]+"${exclure[@]}"}" -print0 2>/dev/null | sort -z
}

compter_videos() {
  NB_VIDEOS=$(lister_videos | tr -cd '\0' | wc -c | tr -d ' ')
}

# ------------------------------------------------------------ menu interactif
# lire_touche : place dans KEY UP / DOWN / LEFT / RIGHT / ENTER / ESC / EOF
# ou le caractère tapé.
lire_touche() {
  local k rest
  KEY=""
  IFS= read -rsn1 k || { KEY="EOF"; return; }
  if [ "$k" = $'\033' ]; then
    rest=""
    read -rsn2 -t 1 rest
    case "$rest" in
      '[A') KEY="UP" ;;
      '[B') KEY="DOWN" ;;
      '[C') KEY="RIGHT" ;;
      '[D') KEY="LEFT" ;;
      *)    KEY="ESC" ;;
    esac
  elif [ -z "$k" ]; then
    KEY="ENTER"
  else
    KEY="$k"
  fi
}

valeur_affichee() { # valeur_affichee INDICE
  local i=$1 k v
  k="${KEYS[$i]}"; v="${!k}"
  case "${TYPES[$i]}" in
    int|choice|choice+) printf '‹ %s ›' "$v" ;;
    *)
      if [ -z "$v" ]; then
        case "$k" in
          PREFIXE|SUFFIXE) printf '\033[2m‹aucun›\033[22m' ;;
          DOSSIER_SORTIE) printf '\033[2m‹à côté de chaque vidéo›\033[22m' ;;
        esac
      else
        printf '%s' "$v"
      fi ;;
  esac
}

apercu() {
  local cols=$COLONNES nb=$NB_CAPTURES rows r c idx h wt ht
  [ "$cols" -gt "$nb" ] && cols=$nb
  rows=$(( (nb + cols - 1) / cols ))
  h=$(( LARGEUR_VIGNETTE * 9 / 16 / 2 * 2 ))
  wt=$(( cols * LARGEUR_VIGNETTE + (cols - 1) * MARGE_INTERNE + 2 * MARGE_EXTERNE ))
  ht=$(( rows * h + (rows - 1) * MARGE_INTERNE + 2 * MARGE_EXTERNE ))
  printf ' Planche obtenue : %d colonnes × %d lignes, environ %d × %d px (vignettes 16:9)\n' \
    "$cols" "$rows" "$wt" "$ht"
  if [ "$cols" -le 16 ] && [ "$rows" -le 8 ]; then
    for ((r = 0; r < rows; r++)); do
      printf '   '
      for ((c = 0; c < cols; c++)); do
        idx=$(( r * cols + c ))
        if [ "$idx" -lt "$nb" ]; then printf '▇▇ '; else printf '·· '; fi
      done
      printf '\n'
    done
  fi
}

dessiner() { # dessiner SELECTION
  local sel=$1 i pad label marque
  printf '\033[H\033[2J'
  printf '\033[1m PLANCHE CONTACT VIDÉO\033[0m\n'
  printf ' Dossier : %s\n' "$PWD"
  printf ' %s vidéo(s) trouvée(s) (sous-dossiers compris)\n\n' "$NB_VIDEOS"
  for ((i = 0; i < NB_KEYS; i++)); do
    label="${LABELS[$i]}"
    pad=$(( 30 - ${#label} )); [ $pad -lt 1 ] && pad=1
    marque=" "
    if [ "$i" -eq "$sel" ]; then marque="▶"; printf '\033[7m'; fi
    printf ' %s %s%*s' "$marque" "$label" "$pad" ''
    if [ "${KEYS[$i]}" = "QUALITE" ] && [ "$FORMAT" != "jpg" ]; then
      printf '\033[2m(jpg uniquement)\033[22m'
    else
      valeur_affichee "$i"
    fi
    printf '\033[0m\n'
  done
  if [ "$sel" -eq "$NB_KEYS" ]; then printf '\033[7m\033[1m'; else printf '\033[1m'; fi
  printf '\n ▶ LANCER LE TRAITEMENT\033[0m\n\n'
  apercu
  printf '\n'
  if [ "$sel" -lt "$NB_KEYS" ]; then printf ' \033[2m%s\033[22m\n' "${HINTS[$sel]}"; fi
  [ -n "$MSG" ] && printf ' \033[33m%s\033[0m\n' "$MSG"
  MSG=""
  printf '\n \033[2m↑↓ choisir   ←→ modifier   Entrée saisir/lancer   s sauvegarder   d défauts   q quitter\033[22m\n'
}

ajuster() { # ajuster INDICE SENS(+1/-1)
  local i=$1 dir=$2 k v c n idx pas
  k="${KEYS[$i]}"; v="${!k}"
  case "${TYPES[$i]}" in
    int)
      pas=${STEPS[$i]}
      v=$(( v + dir * pas ))
      [ "$v" -lt "${MINS[$i]}" ] && v=${MINS[$i]}
      [ "$v" -gt "${MAXS[$i]}" ] && v=${MAXS[$i]}
      printf -v "$k" '%s' "$v" ;;
    choice|choice+)
      n=0; idx=-1
      for c in ${CHOICES[$i]}; do
        [ "$c" = "$v" ] && idx=$n
        n=$((n + 1))
      done
      idx=$(( (idx + dir + n) % n ))
      n=0
      for c in ${CHOICES[$i]}; do
        [ $n -eq $idx ] && printf -v "$k" '%s' "$c"
        n=$((n + 1))
      done ;;
  esac
}

editer() { # editer INDICE : saisie au clavier d'une valeur
  local i=$1 k val
  k="${KEYS[$i]}"
  case "${TYPES[$i]}" in
    choice) ajuster "$i" 1; return ;;
  esac
  printf '\n'
  case "${TYPES[$i]}" in
    int) printf ' %s : entier de %s à %s' "${LABELS[$i]}" "${MINS[$i]}" "${MAXS[$i]}" ;;
    *)   printf ' %s' "${LABELS[$i]}" ;;
  esac
  printf ' (Entrée seule = inchangé)\n'
  printf '\033[?25h'
  IFS= read -r -e -p " ➜ " val
  printf '\033[?25l'
  [ -z "$val" ] && return
  case "$k" in
    PREFIXE|SUFFIXE|DOSSIER_SORTIE) [ "$val" = "-" ] && val="" ;;
  esac
  if valider "$i" "$val"; then
    printf -v "$k" '%s' "$val"
    case "$k" in EXTENSIONS|PREFIXE) compter_videos ;; esac
  else
    MSG="Valeur refusée : $ERR."
  fi
}

menu() {
  local sel=0 k v
  trap 'printf "\033[?25h\n"' EXIT
  printf '\033[?25l'
  while true; do
    dessiner "$sel"
    lire_touche
    case "$KEY" in
      UP)    sel=$(( (sel + NB_KEYS) % (NB_KEYS + 1) )) ;;
      DOWN)  sel=$(( (sel + 1) % (NB_KEYS + 1) )) ;;
      LEFT)  [ "$sel" -lt "$NB_KEYS" ] && ajuster "$sel" -1 ;;
      RIGHT|' ') [ "$sel" -lt "$NB_KEYS" ] && ajuster "$sel" 1 ;;
      ENTER)
        if [ "$sel" -eq "$NB_KEYS" ]; then break; else editer "$sel"; fi ;;
      l|L) break ;;
      s|S) sauver_conf; MSG="Réglages sauvegardés dans $CONF_FILE" ;;
      d|D)
        for k in "${KEYS[@]}"; do v="DEF_$k"; printf -v "$k" '%s' "${!v}"; done
        compter_videos
        MSG="Réglages par défaut rétablis (non sauvegardés)." ;;
      q|Q|EOF) printf '\033[?25h\n'; trap - EXIT; exit 0 ;;
    esac
    if [ "$sel" -lt "$NB_KEYS" ]; then
      case "$KEY:${KEYS[$sel]}" in
        LEFT:EXTENSIONS|LEFT:PREFIXE|RIGHT:EXTENSIONS|RIGHT:PREFIXE) compter_videos ;;
      esac
    fi
  done
  printf '\033[?25h'
  trap - EXIT
  printf '\033[H\033[2J'
}

# --------------------------------------------------------------- traitement
qualite_ffmpeg() { # % -> échelle -q:v de ffmpeg (2 = meilleure, 31 = pire)
  local q=$(( 31 - (QUALITE * 29 + 50) / 100 ))
  [ $q -lt 2 ] && q=2
  [ $q -gt 31 ] && q=31
  echo "$q"
}

traiter_video() {
  local video="$1" dir base sortie duree tmp i t lignes

  dir=$(dirname "$video")
  base=$(basename "$video")
  base="${base%.*}"

  if [ -n "$DOSSIER_SORTIE" ]; then
    mkdir -p "$DOSSIER_SORTIE" || return 1
    sortie="$DOSSIER_SORTIE/${PREFIXE}${base}${SUFFIXE}.${FORMAT}"
  else
    sortie="$dir/${PREFIXE}${base}${SUFFIXE}.${FORMAT}"
  fi

  if [ -e "$sortie" ] && [ "$ECRASER" != "oui" ]; then
    echo "  = déjà présent, ignoré : $sortie"
    return 0
  fi

  duree=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$video" 2>/dev/null)
  if [ -z "$duree" ] || [ "$duree" = "N/A" ] || \
     ! LC_ALL=C awk -v d="$duree" 'BEGIN{exit !(d>0)}'; then
    echo "  ! durée illisible, ignoré : $video" >&2
    return 1
  fi

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/planche.XXXXXX") || return 1

  # Instants répartis uniformément : au milieu de N tranches égales,
  # donc jamais sur l'image noire du tout début ni de la toute fin.
  i=0
  for t in $(LC_ALL=C awk -v d="$duree" -v n="$NB_CAPTURES" \
               'BEGIN{for(i=0;i<n;i++) printf "%.3f\n", d*(i+0.5)/n}'); do
    i=$((i+1))
    ffmpeg -nostdin -v error -y -ss "$t" -i "$video" -frames:v 1 \
      -vf "scale=${LARGEUR_VIGNETTE}:-2" "$tmp/$(printf '%04d' "$i").png" \
      || echo "    ! capture $i impossible (t=${t}s)" >&2
  done

  if [ ! -f "$tmp/0001.png" ]; then
    echo "  ! aucune capture obtenue : $video" >&2
    rm -rf "$tmp"; return 1
  fi

  # Si certaines captures ont échoué, on adapte au nombre réellement obtenu.
  local obtenues cols
  obtenues=$(ls "$tmp"/*.png | wc -l | tr -d ' ')
  cols=$COLONNES
  [ "$obtenues" -lt "$cols" ] && cols=$obtenues
  lignes=$(( (obtenues + cols - 1) / cols ))

  local opts_sortie=()
  [ "$FORMAT" = "jpg" ] && opts_sortie=(-q:v "$(qualite_ffmpeg)")

  # Les noms 0001.png… ne sont pas forcément contigus si une capture a échoué :
  # on passe par un motif glob, qui lit tout ce qui existe dans l'ordre.
  ffmpeg -nostdin -v error -y -pattern_type glob -i "$tmp/*.png" \
    -vf "tile=${cols}x${lignes}:padding=${MARGE_INTERNE}:margin=${MARGE_EXTERNE}:color=${COULEUR_FOND}" \
    -frames:v 1 "${opts_sortie[@]+"${opts_sortie[@]}"}" "$sortie"
  local rc=$?

  rm -rf "$tmp"
  if [ $rc -eq 0 ]; then
    echo "  ✓ $sortie  (${obtenues} captures, ${cols}×${lignes})"
  else
    echo "  ! échec de l'assemblage : $video" >&2
  fi
  return $rc
}

lancer() {
  local total=0 ok=0 ko=0 video

  if [ -z "${EXTENSIONS// /}" ]; then echo "Aucune extension configurée."; return 1; fi

  echo "Recherche des vidéos dans $PWD …"
  while IFS= read -r -d '' video <&3; do
    total=$((total+1))
    echo "[$total] $video"
    if traiter_video "$video"; then ok=$((ok+1)); else ko=$((ko+1)); fi
  done 3< <(lister_videos)

  echo
  echo "Terminé : $total vidéo(s), $ok réussie(s), $ko en échec."
  [ $ko -eq 0 ]
}

# ------------------------------------------------------------ ligne de commande
usage() {
  cat <<EOF
Usage : $(basename "$0") [options]

Sans option, un menu interactif permet de régler les paramètres. Les options
préremplissent le menu ; avec -y, le traitement démarre sans menu.
Les réglages sauvegardés (touche « s » du menu) sont dans :
  $CONF_FILE

  -n NB     nombre de captures par vidéo        (défaut $DEF_NB_CAPTURES)
  -c NB     colonnes du damier                  (défaut $DEF_COLONNES)
  -w PX     largeur d'une capture               (défaut $DEF_LARGEUR_VIGNETTE)
  -m PX     marge entre les images              (défaut $DEF_MARGE_INTERNE)
  -M PX     marge autour du damier              (défaut $DEF_MARGE_EXTERNE)
  -b COUL   couleur de fond (black, 0x202020…)  (défaut $DEF_COULEUR_FOND)
  -f FMT    format de sortie : jpg ou png       (défaut $DEF_FORMAT)
  -q PCT    qualité JPEG de 1 à 100             (défaut $DEF_QUALITE)
  -p TXT    préfixe du fichier de sortie        (défaut $DEF_PREFIXE)
  -s TXT    suffixe du fichier de sortie        (défaut aucun)
  -o DIR    dossier de sortie                   (défaut : à côté de la vidéo)
  -F        écraser les planches existantes
  -y        lancer directement, sans menu
  -h        cette aide
EOF
}

# --------------------------------------------------------------------- main
verifier_outils
charger_conf

SANS_MENU=0
while getopts "n:c:w:m:M:b:p:s:f:q:o:Fyh" opt; do
  case "$opt" in
    n) regler NB_CAPTURES "$OPTARG" ;;
    c) regler COLONNES "$OPTARG" ;;
    w) regler LARGEUR_VIGNETTE "$OPTARG" ;;
    m) regler MARGE_INTERNE "$OPTARG" ;;
    M) regler MARGE_EXTERNE "$OPTARG" ;;
    b) regler COULEUR_FOND "$OPTARG" ;;
    f) regler FORMAT "$OPTARG" ;;
    q) regler QUALITE "$OPTARG" ;;
    p) regler PREFIXE "$OPTARG" ;;
    s) regler SUFFIXE "$OPTARG" ;;
    o) regler DOSSIER_SORTIE "$OPTARG" ;;
    F) ECRASER="oui" ;;
    y) SANS_MENU=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

# Pas de menu si on n'est pas dans un terminal (script, cron, redirection).
[ -t 0 ] && [ -t 1 ] || SANS_MENU=1

if [ $SANS_MENU -eq 0 ]; then
  compter_videos
  menu
fi
lancer
