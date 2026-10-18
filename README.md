# Cappella Mac - portage Mac OS

Objectif : reproduire Cappella 3.7 sur Mac Apple Silicon. Ce projet est une
**première implémentation expérimentale, pas encore compilée ni exécutée sur macOS**.
Il ne constitue pas encore un remplacement complet du logiciel.

Swift, SwiftUI et AVFoundation ; aucune dépendance de paquet externe.
Cible minimale : macOS 13. Architecture distribuable : ARM64.
L'exécutable Windows n'est pas utilisé par l'application Swift.

## Compiler sur le Mac de ton collègue

Installer Xcode, l'ouvrir une fois pour terminer l'installation, puis ouvrir le
Terminal dans ce dossier et exécuter :

```sh
swift test --arch arm64
bash scripts/build-macos.sh
open "dist/Cappella Mac.app"
```

Si une commande échoue, conserver le message d'erreur complet pour correction.

Le script produit `dist/Cappella Mac.app` et `dist/CappellaMac-arm64.zip`.
La signature est locale/ad hoc ; la distribution Developer ID et la notarisation
ne sont pas configurées. Une archive téléchargée peut être bloquée par macOS.

## Compiler sans Mac personnel

Le workflow [.github/workflows/macos.yml](.github/workflows/macos.yml) prévoit les
tests et le packaging sur un runner Apple Silicon `macos-15`. Après dépôt des
sources sur GitHub, lancer « Native macOS ARM64 » dans Actions et télécharger
l'artefact. Aucun workflow distant n'a été déclenché ici.

## Essayer un DetX

1. Créer un document et choisir la cadence avant l'import (25 i/s par défaut).
2. Cliquer sur « Importer un DetX… » et sélectionner une copie du fichier.
3. Ouvrir la vidéo correspondante : les anciens chemins Windows ne sont pas résolus sur Mac.
4. Modifier les textes, rôles et bornes temporelles.
5. Enregistrer avec Cmd+S au format de travail `.cappellaproject`.
6. Exporter vers un **nouveau** `.detx`, puis vérifier sa réouverture dans Cappella Windows.

Le document de travail conserve le XML importé, portraits et métadonnées compris.
L'import prend en charge le profil de phrase `lipsync / text / lipsync` observé
dans l'exemple fourni. Les structures plus riches sont refusées à l'import.
Les rôles source inutilisés restent dans l'export pour conserver leurs données.
La sérialisation XML n'est pas identique octet par octet.
La compatibilité de l'export avec Cappella Windows reste à vérifier.

Le média doit être sélectionné à chaque session. La bande rythmo place les phrases
dans le temps ; elle ne reproduit pas encore l'étirement et l'alignement labial
de Cappella. La projection est une prévisualisation dans une feuille, pas une
sortie indépendante sur un deuxième écran.

## Tests et analyse

Pour tester un DetX réel localement sur Mac sans le publier :

```sh
CAPPELLA_DETX_PATH="/chemin/Elliott from Earth#107.detx" swift test --arch arm64
```

L'audit structurel Python fonctionne aussi sous Windows, en lecture seule :

```powershell
python scripts/inspect_detx.py 'C:\chemin\fichier.detx' --fps 25
```

Le fichier fourni ne déclare pas sa cadence. 25 i/s est une hypothèse compatible
avec ses timecodes, pas une valeur confirmée par le XML.
Les tests Swift n'ont pas été exécutés dans cet environnement Windows sans Swift.

L'[état du portage](docs/PORTAGE.md) détaille ce qui reste à reproduire.
Les fichiers historiques dans `assets/` sont exclus du build Swift et du suivi Git.
Le DetX privé reste dans son emplacement d'origine, hors du projet.

Références : [Swift Package Manager](https://docs.swift.org/main/documentation/packagemanagerdocs/),
[documents SwiftUI](https://developer.apple.com/documentation/SwiftUI/DocumentGroup),
[runners GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
