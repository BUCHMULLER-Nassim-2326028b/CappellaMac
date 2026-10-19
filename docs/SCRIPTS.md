# Scripts

Les commandes se lancent depuis la racine du dépôt. Les points d'entrée
de compilation restent scripts/build-macos.sh et scripts/build-windows.ps1.

## Compilation et distribution

| Script | Utilisé par |
|---|---|
| build-macos.sh | Développement Mac et workflow macos.yml |
| build-icons.swift | build-macos.sh : génération des icônes Mac |
| build-windows.ps1 | Développement Windows et workflow windows.yml |
| build-windows-installer.ps1 | Création du Setup Inno Setup à partir du binaire Windows existant ; développement et workflow windows.yml |
| prepare-windows.ps1 | Préparation des projections ; également appelée par build-windows.ps1 si nécessaire |
| lib/WindowsBuild.ps1 | Fonction commune de synchronisation du support WinUI/WinAppSDK, appelée par les deux scripts Windows |
| build-windows-icons.ps1 | build-windows.ps1 : génération des icônes Windows |
| embed-windows-resources.ps1 | build-windows.ps1 : ressources de l'exécutable |
| windows/Installer-runtime.ps1 | Installation du runtime WinUI pour le développement, la CI et le Setup (extrait temporairement, absent du ZIP et du dossier installé) |

Les projections .windows sont générées à partir de windows/projections.json.
Leur empreinte permet à -SkipPrepare de conserver un cache à jour.
Modifier le support manuel dans windows/Support, jamais uniquement dans le cache.

## Contrôles conservés

| Script | Appelant / objectif |
|---|---|
| smoke_macos.py | macos.yml : lancement du bundle Mac, avec et sans DetX |
| check_finder_open.swift | macos.yml : ouverture Finder à froid, à chaud et réouverture du même fichier |
| check_timeline_text.swift | macos.yml : saisie native et clavier dans la bande |
| check_audio_preparation.swift | macos.yml : préparation VO/VI à quatre pistes |
| smoke-windows.ps1 | windows.yml : lancement, chargement DetX et saisie sur la bande |
| check-windows-activation.ps1 | windows.yml : instances indépendantes et arrêt des processus |
| make_load_fixture.py | windows.yml : création d'un DetX synthétique de 1 000 phrases |

Les tests des menus Mac sont dans Tests/CappellaSessionTests/EditorMenuTests.swift ;
ils passent avec swift test. Les autres tests sont répartis par module dans Tests.

Pour exécuter les contrôles du package :

    swift test --arch arm64

Sur Windows avec les projections préparées :

    swift test -c release -j 4

Un DetX local peut être fourni aux tests du moteur sans le publier :

    CAPPELLA_DETX_PATH="/chemin/exemple.detx" swift test --arch arm64

Les workflows et le [guide de release](RELEASES.md) décrivent la production des
artefacts. Les captures du runner sont facultatives si son accès écran est refusé.
