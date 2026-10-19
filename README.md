<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="packaging/Resources/CappellaLogo_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="packaging/Resources/CappellaLogo.png">
    <img src="packaging/Resources/CappellaLogo.png" alt="Logo Cappella" width="240">
  </picture>
</p>

<h1 align="center">Cappella</h1>

<p align="center">
  Une nouvelle vie pour la bande rythmo.<br>
  Réécriture native en Swift pour macOS et Windows.
</p>

<p align="center">
  <a href="https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases">Télécharger</a>
  · <a href="#roadmap">Roadmap</a>
  · <a href="#ce-qui-reste-à-faire">Ce qui manque</a>
  · <a href="docs/RELEASES.md">Créer une release</a>
</p>

## Le projet

Cappella est un outil de travail pour le doublage : script, vidéo et dialogues
synchronisés sur une bande rythmo. Ce projet en propose une réécriture native,
réalisée sans les sources du logiciel d'origine.

**Retrouver d'abord les fonctions et les habitudes de Cappella, puis aller plus loin.**
Le but final est de faire évoluer le logiciel : améliorer sa fluidité, son ergonomie
et ses outils, tout en conservant les projets et les méthodes de travail existantes.

Le projet est en développement. La fidélité complète à l'original et la compatibilité
avec tous les projets doivent encore être validées en conditions réelles.

## Plateformes et téléchargements

| Plateforme | Architecture | Distribution |
|---|---|---|
| macOS | Apple Silicon · ARM64 | Portable : ZIP contenant Cappella.app |
| Windows | Intel / AMD · x64 | Portable ZIP et Setup EXE |
| Windows | ARM64 | Portable ZIP et Setup EXE ; build native configurée dans Actions, à valider |

Les fichiers sont disponibles dans les [releases GitHub](https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases)
lorsqu'une version est publiée. Chaque distribution possède aussi son propre
artefact dans GitHub Actions.

Convention de nommage :

~~~text
Cappella-VERSION-macOS-arm64-Portable.zip
Cappella-VERSION-Windows-x64-Portable.zip
Cappella-VERSION-Windows-x64-Setup.exe
Cappella-VERSION-Windows-arm64-Portable.zip
Cappella-VERSION-Windows-arm64-Setup.exe
~~~

Sur Windows, le **Setup** installe l'application, propose les raccourcis et prépare
le Windows App Runtime 1.7 de la bonne architecture si nécessaire. Le **portable**
s'extrait dans un dossier ; il nécessite ce runtime installé séparément.
Sur Mac, extraire le ZIP puis déplacer Cappella.app dans Applications.

## Déjà en place

- **Espace de travail familier** : script à gauche, vidéo à droite, timecode et
  bande rythmo à quatre pistes, panneaux redimensionnables et thèmes clair/sombre.
- **Édition sur la bande** : saisie au clic simple, rôles et portraits, signes,
  menus contextuels, sélection des pistes et raccourcis.
- **Navigation synchronisée** : repères, boucles, plans, zoom et barre de défilement horizontale.
- **Vidéo et audio** : médias associés au projet, audio séparé et commutation VO/VI,
  avec des différences de prise en charge entre les plateformes.
- **Documents** : lecture/écriture DetX, format de travail .cappellaproject,
  préférences persistantes et sauvegarde automatique désactivable.
- **Sessions** : remplacement du projet courant avec demande d'enregistrement,
  et possibilité de lancer plusieurs instances indépendantes.

Ces fonctions sont implémentées ; leur présence ne garantit pas encore une parité
complète avec chaque comportement de l'original.

## Ce qui reste à faire

| Chantier | État actuel |
|---|---|
| Parité Mac / Windows | L'enregistrement microphone et la détection automatique des plans restent propres au Mac. La recherche et la projection Windows sont moins complètes. |
| Audio Windows | Étendre la couverture des dispositions multicanales et des formats AIFF/AIFC ; valider les codecs avec des médias réels. |
| Compatibilité des projets | Vérifier davantage de variantes DetX, les anciens .det et la réouverture des exports dans le Cappella d'origine. |
| Outils métier avancés | Compléter le protocole Orphée/FTDI, le sous-titrage UER et l'impression d'origine. |
| Lecture inverse | Navigation par recherches d'images, sans restitution audio inversée. |
| Validation en séance | Comparer typographie, saisie, synchronisation et fluidité sur différents écrans et projets longs. |
| Distribution | Valider Windows ARM64 et le cycle installation/désinstallation ; préparer la signature Windows et la notarisation Mac. |

Les limites techniques sont détaillées dans [Architecture](docs/ARCHITECTURE.md)
et [Windows](docs/WINDOWS.md).

## Roadmap

Une progression par étapes, sans dates promises. Certains chantiers avancent en parallèle.

~~~mermaid
flowchart LR
    A["1 · Socle natif<br/>En place<br/>Swift · moteur DetX · interfaces Mac et Windows"]
    B["2 · Fidélité à Cappella<br/>En cours<br/>Bande rythmo · saisie · menus · audio"]
    C["3 · Parité et stabilité<br/>À compléter<br/>Formats · outils métier · validation en séance"]
    D["4 · Distribution fiable<br/>En cours<br/>ARM64 · portable et setup · signature"]
    E["5 · Aller plus loin<br/>Objectif final<br/>Améliorer le logiciel et ses outils"]

    A --> B --> C --> D --> E
~~~

Une fois le socle fiable et les usages d'origine couverts, l'objectif est
**d'améliorer Cappella lui-même** : une bande plus fluide, une édition plus agréable,
des outils de recherche et de navigation plus puissants, et une meilleure
interopérabilité. Les évolutions seront guidées par les retours des personnes qui
utilisent le logiciel en séance.

## Compiler

Les interfaces partagent le moteur CappellaCore. Le Mac utilise SwiftUI/AppKit ;
Windows utilise WinUI 3 avec Swift-WinRT.

### macOS ARM64

Sur un Mac Apple Silicon équipé des outils de développement Apple :

~~~bash
bash scripts/build-macos.sh
open dist/Cappella.app
~~~

La cible minimale du package est macOS 13. Les workflows vérifient également
l'ouverture sur macOS 15 et 26. La signature actuelle est ad hoc.

### Windows x64 et ARM64

Installer Swift pour Windows, les outils C++ de Visual Studio et un Windows SDK
adaptés à l'architecture cible :

~~~powershell
.scriptsuild-windows.ps1 -Architecture x64
.scriptsuild-windows.ps1 -SkipPrepare -Architecture x64
~~~

La deuxième commande réutilise les projections WinRT si leur configuration
n'a pas changé. Remplacer x64 par arm64 pour une chaîne de compilation ARM64.
Le workflow Windows dispose de runners natifs pour les deux architectures.

Pour générer le Setup à partir du binaire compilé, avec Inno Setup 6 installé :

~~~powershell
.scriptsuild-windows-installer.ps1 -Architecture x64
~~~

Les builds sont en release par défaut ; ajouter -Configuration debug pour le
développement. Les prérequis et les commandes complètes sont dans [Windows](docs/WINDOWS.md).

## Participer

Les retours utiles incluent la plateforme, la version, les étapes pour reproduire
le problème et le comportement attendu dans l'original. Pour un souci de compatibilité,
un petit projet d'exemple sans médias confidentiels aide à comprendre le cas.

- [Signaler un problème ou proposer une amélioration](https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/issues)
- [Architecture et limites](docs/ARCHITECTURE.md)
- [Scripts et contrôles CI](docs/SCRIPTS.md)
- [Préparer une release GitHub](docs/RELEASES.md)
- [Références du logiciel d'origine](docs/reference/README.md)
