#!/usr/bin/env bash
# planche-contact.sh — génère une planche contact (damier de captures) pour
# chaque vidéo du dossier courant et de ses sous-dossiers.
#
# Prérequis (macOS) :  brew install ffmpeg
# Utilisation       :  cd /dossier/de/videos && /chemin/vers/planche-contact.sh
#
# Compatible avec bash 3.2 (celui de macOS).

set -u

CONF_FILE="$HOME/.planche-contact.conf"

# ---------------------------------------------------------------- paramètres
NB_CAPTURES=12          # nombre de captures par vidéo
COLONNES=4              # nombre de colonnes du damier
LARGEUR_VIGNETTE=480    # largeur de chaque capture (px)
MARGE_INTERNE=6         # marge entre les images (px)
MARGE_EXTERNE=6         # marge autour du damier (px)
COULEUR_FOND="black"    # couleur de fond / des marges (nom ffmpeg ou 0xRRGGBB)
PREFIXE="planche_"      # préfixe du fichier de sortie
FORMAT="jpg"            # jpg ou png
QUALITE_JPG=3           # 2 (excellente) … 31 (mauvaise)
EXTENSIONS="mp4 mov mkv avi m4v wmv flv webm mpg mpeg mts m2ts ts"
DOSSIER_SORTIE=""       # vide = à côté de la vidéo ; sinon chemin (relatif ou absolu)
ECRASER="non"           # oui / non : remplacer une planche déjà existante

charger_conf() {
  # shellcheck disable=SC1090
  [ -f "$CONF_FILE" ] && . "$CONF_FILE"
}

sauver_conf() {
  {
    for v in NB_CAPTURES COLONNES LARGEUR_VIGNETTE MARGE_INTERNE MARGE_EXTERNE \
             COULEUR_FOND PREFIXE FORMAT QUALITE_JPG EXTENSIONS DOSSIER_SORTIE ECRASER; do
      printf '%s=%q\n' "$v" "${!v}"
    done
  } > "$CONF_FILE"
}

# ------------------------------------------------------------------- outils
verifier_outils() {
  for outil in ffmpeg ffprobe; do
    if ! command -v "$outil" >/dev/null 2>&1; then
      echo "Erreur : '$outil' est introuvable. Installez-le avec :  brew install ffmpeg" >&2
      exit 1
    fi
  done
}

est_entier_positif() { case "$1" in ''|*[!0-9]*|0) return 1 ;; *) return 0 ;; esac; }
est_entier()         { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# --------------------------------------------------------------------- menu
saisir() { # saisir "invite" VARIABLE validateur
  local invite="$1" var="$2" valid="$3" val
  printf '%s [%s] : ' "$invite" "${!var}"
  read -r val
  [ -z "$val" ] && return
  if [ "$valid" = "-" ] || $valid "$val"; then
    printf -v "$var" '%s' "$val"
  else
    echo "  Valeur invalide, inchangée."
    sleep 1
  fi
}

valide_format() { case "$1" in jpg|png) return 0 ;; *) return 1 ;; esac; }
valide_oui_non() { case "$1" in oui|non) return 0 ;; *) return 1 ;; esac; }
valide_qualite() { est_entier_positif "$1" && [ "$1" -le 31 ]; }

afficher_menu() {
  clear
  cat <<EOF
=====================================================
   PLANCHE CONTACT VIDÉO
   Dossier : $(pwd)
=====================================================
  1) Nombre de captures par vidéo ....... $NB_CAPTURES
  2) Nombre de colonnes ................. $COLONNES
  3) Largeur d'une capture (px) ......... $LARGEUR_VIGNETTE
  4) Marge entre les images (px) ........ $MARGE_INTERNE
  5) Marge autour du damier (px) ........ $MARGE_EXTERNE
  6) Couleur de fond .................... $COULEUR_FOND
  7) Préfixe du fichier de sortie ....... $PREFIXE
  8) Format (jpg / png) ................. $FORMAT
  9) Qualité JPEG (2=max … 31=min) ...... $QUALITE_JPG
 10) Extensions vidéo traitées .......... $EXTENSIONS
 11) Dossier de sortie (vide = à côté) .. ${DOSSIER_SORTIE:-<à côté de la vidéo>}
 12) Écraser les planches existantes .... $ECRASER

  s) Sauvegarder ces réglages   l) Lancer le traitement   q) Quitter
-----------------------------------------------------
EOF
}

menu() {
  local choix
  while true; do
    afficher_menu
    printf 'Votre choix : '
    read -r choix
    case "$choix" in
      1)  saisir "Nombre de captures" NB_CAPTURES est_entier_positif ;;
      2)  saisir "Nombre de colonnes" COLONNES est_entier_positif ;;
      3)  saisir "Largeur d'une capture (px)" LARGEUR_VIGNETTE est_entier_positif ;;
      4)  saisir "Marge entre les images (px)" MARGE_INTERNE est_entier ;;
      5)  saisir "Marge autour du damier (px)" MARGE_EXTERNE est_entier ;;
      6)  saisir "Couleur de fond (ex. black, white, 0x202020)" COULEUR_FOND - ;;
      7)  printf 'Préfixe [%s] (tapez - pour aucun) : ' "$PREFIXE"
          read -r val
          [ "$val" = "-" ] && PREFIXE="" || { [ -n "$val" ] && PREFIXE="$val"; } ;;
      8)  saisir "Format (jpg ou png)" FORMAT valide_format ;;
      9)  saisir "Qualité JPEG (2 à 31)" QUALITE_JPG valide_qualite ;;
      10) saisir "Extensions séparées par des espaces" EXTENSIONS - ;;
      11) printf 'Dossier de sortie [%s] (tapez - pour revenir à "à côté de la vidéo") : ' "$DOSSIER_SORTIE"
          read -r val
          [ "$val" = "-" ] && DOSSIER_SORTIE="" || { [ -n "$val" ] && DOSSIER_SORTIE="$val"; } ;;
      12) saisir "Écraser les planches existantes (oui/non)" ECRASER valide_oui_non ;;
      s|S) sauver_conf; echo "Réglages sauvegardés dans $CONF_FILE"; sleep 1 ;;
      l|L) return 0 ;;
      q|Q) exit 0 ;;
    esac
  done
}

# --------------------------------------------------------------- traitement
traiter_video() {
  local video="$1" dir base sortie duree tmp i t lignes

  dir=$(dirname "$video")
  base=$(basename "$video")
  base="${base%.*}"

  if [ -n "$DOSSIER_SORTIE" ]; then
    mkdir -p "$DOSSIER_SORTIE" || return 1
    sortie="$DOSSIER_SORTIE/${PREFIXE}${base}.${FORMAT}"
  else
    sortie="$dir/${PREFIXE}${base}.${FORMAT}"
  fi

  if [ -e "$sortie" ] && [ "$ECRASER" != "oui" ]; then
    echo "  = déjà présent, ignoré : $sortie"
    return 0
  fi

  duree=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$video" 2>/dev/null)
  if [ -z "$duree" ] || [ "$duree" = "N/A" ] || \
     ! awk -v d="$duree" 'BEGIN{exit !(d>0)}'; then
    echo "  ! durée illisible, ignoré : $video" >&2
    return 1
  fi

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/planche.XXXXXX") || return 1

  # Instants répartis uniformément : au milieu de N tranches égales,
  # donc jamais sur l'image noire du tout début ni de la toute fin.
  i=0
  for t in $(awk -v d="$duree" -v n="$NB_CAPTURES" \
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
  [ "$FORMAT" = "jpg" ] && opts_sortie=(-q:v "$QUALITE_JPG")

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
  local args=() ext premier=1 total=0 ok=0 ko=0 video

  for ext in $EXTENSIONS; do
    ext="${ext#.}"
    [ $premier -eq 0 ] && args+=(-o)
    args+=(-iname "*.${ext}")
    premier=0
  done
  if [ $premier -eq 1 ]; then echo "Aucune extension configurée."; return 1; fi

  local exclure=()
  [ -n "$PREFIXE" ] && exclure=(! -name "${PREFIXE}*")

  echo
  echo "Recherche des vidéos dans $(pwd) …"
  while IFS= read -r -d '' video <&3; do
    total=$((total+1))
    echo "[$total] $video"
    if traiter_video "$video"; then ok=$((ok+1)); else ko=$((ko+1)); fi
  done 3< <(find . -type f \( "${args[@]}" \) \
              "${exclure[@]+"${exclure[@]}"}" -print0 2>/dev/null | sort -z)

  echo
  echo "Terminé : $total vidéo(s), $ok réussie(s), $ko en échec."
}

# --------------------------------------------------------------------- main
verifier_outils
charger_conf
menu
lancer
