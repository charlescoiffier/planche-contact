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

Le menu s'affiche. Tapez le numéro d'un réglage pour le modifier (Entrée conserve la valeur actuelle), puis `l` pour lancer le traitement.

| Touche | Action |
|---|---|
| `1` à `12` | Modifier le réglage correspondant |
| `s` | Sauvegarder les réglages dans `~/.planche-contact.conf` (rechargés au lancement suivant) |
| `l` | Lancer le traitement |
| `q` | Quitter |

## Réglages

| # | Réglage | Défaut |
|---|---|---|
| 1 | Nombre de captures par vidéo | 12 |
| 2 | Nombre de colonnes du damier | 4 |
| 3 | Largeur d'une capture (px) | 480 |
| 4 | Marge entre les images (px) | 6 |
| 5 | Marge autour du damier (px) | 6 |
| 6 | Couleur de fond (nom ffmpeg ou `0xRRGGBB`) | black |
| 7 | Préfixe du fichier de sortie | `planche_` |
| 8 | Format : `jpg` ou `png` | jpg |
| 9 | Qualité JPEG (2 = meilleure, 31 = plus faible) | 3 |
| 10 | Extensions vidéo traitées | mp4 mov mkv avi m4v wmv flv webm mpg mpeg mts m2ts ts |
| 11 | Dossier de sortie (vide = à côté de la vidéo) | vide |
| 12 | Écraser les planches existantes | non |

## Fonctionnement

- Les vidéos sont recherchées avec `find`, dans le dossier courant et tous ses sous-dossiers, sans tenir compte de la casse des extensions.
- La durée est lue avec `ffprobe`. Les captures sont prises au milieu de N tranches égales de la vidéo : elles sont donc réparties uniformément, sans jamais tomber sur la toute première ou la toute dernière image.
- L'assemblage utilise le filtre `tile` de ffmpeg (marge entre les images et marge extérieure réglables).
- Le fichier produit s'appelle `<préfixe><nom de la vidéo>.<format>`. Par exemple, `vacances/plage.mp4` donne `vacances/planche_plage.jpg`.
- Les fichiers dont le nom commence par le préfixe sont ignorés lors de la recherche.
- Si le nombre de captures n'est pas un multiple du nombre de colonnes, les cases vides prennent la couleur de fond.
- Si certaines captures échouent, la planche est assemblée avec celles obtenues.
- Une planche déjà présente n'est pas régénérée, sauf si le réglage 12 est sur `oui`.
