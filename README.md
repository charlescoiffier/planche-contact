# planche-contact

Script shell pour macOS qui parcourt le dossier courant et ses sous-dossiers, puis génère pour chaque vidéo une **planche contact** : plusieurs captures d'écran réparties uniformément sur la durée de la vidéo, assemblées en damier avec une légère marge, et enregistrées sous le nom de la vidéo précédé d'un préfixe.

Les réglages se modifient dans un menu textuel au lancement du script.

## Installation

```bash
brew install ffmpeg          # fournit ffmpeg et ffprobe
git clone https://github.com/charlescoiffier/planche-contact.git
chmod +x planche-contact/planche-contact.sh
```

Le script est compatible avec le bash 3.2 fourni avec macOS. Aucune autre dépendance.

## Utilisation

Placez-vous dans le dossier à traiter, puis lancez le script :

```bash
cd /dossier/de/videos
/chemin/vers/planche-contact/planche-contact.sh
```

Le menu s'affiche, avec le nombre de vidéos trouvées et un aperçu de la planche (nombre de lignes et de colonnes, taille approximative en pixels).

| Touche | Action |
|---|---|
| `↑` `↓` | Choisir un réglage (la dernière ligne, « Lancer le traitement », démarre le traitement avec Entrée) |
| `←` `→` ou `Espace` | Modifier la valeur : ±1 pour les nombres (±20 px pour la largeur), liste de choix pour la couleur, le format et « écraser » |
| `Entrée` | Saisir une valeur au clavier (nombre, couleur libre, préfixe, extensions, dossier) |
| `s` | Sauvegarder les réglages dans `~/.planche-contact.conf` (rechargés au lancement suivant) |
| `d` | Rétablir les réglages par défaut |
| `l` | Lancer le traitement |
| `q` | Quitter |

Les valeurs invalides sont refusées avec un message. Pour le préfixe et le dossier de sortie, saisir `-` revient à « aucun » / « à côté de la vidéo ».

### Sans menu : options en ligne de commande

Les options préremplissent le menu et prennent le pas sur les réglages sauvegardés. Avec `-y`, le traitement démarre directement, ce qui permet de l'utiliser dans un autre script.

```bash
planche-contact.sh -n 20 -c 5 -w 360 -p "contact_" -y
```

| Option | Réglage |
|---|---|
| `-n` | Nombre de captures |
| `-c` | Colonnes |
| `-w` | Largeur d'une capture (px) |
| `-m` / `-M` | Marge entre les images / autour du damier (px) |
| `-b` | Couleur de fond |
| `-f` | Format (`jpg` ou `png`) |
| `-q` | Qualité JPEG (1 à 100) |
| `-p` | Préfixe |
| `-o` | Dossier de sortie |
| `-F` | Écraser les planches existantes |
| `-y` | Lancer sans menu (automatique si le script n'est pas lancé dans un terminal) |
| `-h` | Aide |

## Réglages

| Réglage | Défaut |
|---|---|
| Nombre de captures par vidéo | 12 |
| Colonnes du damier | 4 |
| Largeur d'une capture (px) | 480 |
| Marge entre les images (px) | 6 |
| Marge autour du damier (px) | 6 |
| Couleur de fond (nom ffmpeg ou `0xRRGGBB`) | black |
| Format de sortie : `jpg` ou `png` | jpg |
| Qualité JPEG (1 à 100, jpg uniquement) | 95 |
| Préfixe du fichier de sortie | `planche_` |
| Extensions vidéo traitées | mp4 mov mkv avi m4v wmv flv webm mpg mpeg mts m2ts ts |
| Dossier de sortie (vide = à côté de la vidéo) | vide |
| Écraser les planches existantes | non |

## Fonctionnement

- Les vidéos sont recherchées avec `find`, dans le dossier courant et tous ses sous-dossiers, sans tenir compte de la casse des extensions.
- La durée est lue avec `ffprobe`. Les captures sont prises au milieu de N tranches égales de la vidéo : elles sont donc réparties uniformément, sans jamais tomber sur la toute première ou la toute dernière image.
- L'assemblage utilise le filtre `tile` de ffmpeg (marge entre les images et marge extérieure réglables).
- Le fichier produit s'appelle `<préfixe><nom de la vidéo>.<format>`. Par exemple, `vacances/plage.mp4` donne `vacances/planche_plage.jpg`.
- Les fichiers dont le nom commence par le préfixe sont ignorés lors de la recherche.
- Si le nombre de captures n'est pas un multiple du nombre de colonnes, les cases vides prennent la couleur de fond.
- Si certaines captures échouent, la planche est assemblée avec celles obtenues.
- Une planche déjà présente n'est pas régénérée, sauf si « Écraser l'existant » est sur `oui` (ou avec `-F`).
