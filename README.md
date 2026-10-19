# Cappella

Réécriture native de Cappella en Swift : SwiftUI/AppKit sur Mac Apple Silicon,
WinUI 3 avec Swift-WinRT sur Windows x64. Les deux interfaces partagent le moteur
DetX et les règles d'édition de CappellaCore.

Le projet vise la fidélité au logiciel d'origine. Ses sources C++ ne sont pas
disponibles et la parité complète reste à vérifier sur des projets et médias réels.

## Utiliser l'application

L'espace de travail comprend le script à gauche, la vidéo à droite, le timecode
sous le script et quatre pistes de bande rythmo en bas. Cliquer une fois sur une
réplique pour saisir son texte ; le clic droit donne accès au rôle, à la piste et
aux signes. La barre horizontale au-dessus de la rythmo permet de parcourir le projet.
L'image et le son séparé se relient dans les propriétés du projet.

Les documents s'ouvrent et s'enregistrent en DetX ou en format de travail
.cappellaproject. Ouvrir un autre projet remplace le projet courant après la
demande d'enregistrement. Plusieurs instances indépendantes peuvent être lancées.

## Compiler

### macOS ARM64

Sur un Mac Apple Silicon avec les outils de développement Apple :

    bash scripts/build-macos.sh
    open dist/Cappella.app

Résultats : dist/Cappella.app et dist/Cappella-MacOS-arm64.zip.
La cible minimale du package est macOS 13. La signature est ad hoc.

### Windows x64

Installer Swift pour Windows, Visual Studio 2022 avec les outils C++ et un Windows SDK :

    .\scripts\build-windows.ps1

Pour les compilations suivantes, réutiliser les projections WinRT :

    .\scripts\build-windows.ps1 -SkipPrepare

Ajouter -Configuration debug pour une compilation de développement.
Les détails d'installation, les caches et les limites sont dans [Windows](docs/WINDOWS.md).

### GitHub Actions

Les workflows compilent et contrôlent les deux plateformes. Le binaire Mac
construit sur macOS 15 est également ouvert sur macOS 26. Les archives se
téléchargent dans les artefacts Cappella-MacOS-arm64 et Cappella-Windows-x64.

## Développer et distribuer

- [Architecture et limites](docs/ARCHITECTURE.md)
- [Scripts de compilation et contrôles CI](docs/SCRIPTS.md)
- [Version Windows](docs/WINDOWS.md)
- [Créer une release GitHub](docs/RELEASES.md)
- [Références du logiciel d'origine](docs/reference/README.md)

Les caches .build et .windows, les archives dist, les sauvegardes backups et
l'installation d'origine assets sont locaux et ignorés par Git. Les ressources
distribuées et les licences tierces sont conservées dans packaging et windows.
