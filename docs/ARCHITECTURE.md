# Architecture

## Modules

| Dossier | Responsabilité |
|---|---|
| Sources/CappellaCore | Modèle de projet, DetX, signes, règles d'édition, timecodes, routage audio et préférences |
| Sources/CappellaSession | Session Mac, remplacement/enregistrement des documents, événements Finder et adaptation des menus AppKit |
| Sources/CappellaMac | Interface SwiftUI/AppKit, transport AVFoundation, édition sur bande, projection, enregistrement et analyse des plans |
| Sources/CappellaWindows | Interface WinUI 3, document Windows, transport multimédia et édition sur bande |
| Sources/CWindowsInterop | Pont natif pour rattacher les sélecteurs Windows à la fenêtre |
| windows/Support | Support Swift-WinRT intégré aux projections générées |
| packaging | Métadonnées du bundle Mac et ressources distribuées |
| Tests | Tests du moteur commun et des adaptateurs de chaque plateforme |

CappellaSession réexporte CappellaCore pour ses clients Mac. Swift Package Manager
inclut automatiquement les fichiers Swift de chaque cible ; les fichiers propres
à Windows restent dans la cible Windows.

## Interface Windows

WindowsEditor conserve l'état de présentation et relie les événements.
Ses extensions répartissent les responsabilités :

| Fichier | Responsabilité |
|---|---|
| WindowsLayout | Disposition, séparateurs, barre de titre et thème de la fenêtre |
| WindowsCartouche | Timecode, boucle courante, durée et état VO/VI |
| WindowsScriptView | Liste des répliques et mise à jour de leur sélection |
| WindowsBand | Dessin de la bande, signes et interactions du pointeur |
| WindowsTimelineScroll | Barre horizontale et navigation dans le projet |
| WindowsTimelineMotion | Interpolation du transport et animation du défilement |
| WindowsTimelineText | Saisie native invisible, sélection et curseur dessinés sur la bande |
| WindowsMenus | Menus, coches et raccourcis |
| WindowsDesktopInput | Interception des messages clavier, suivi du redimensionnement et fermeture |
| WindowsDialogs | Infrastructure des dialogues, catégories, recherche et actions communes |
| WindowsFileDialogs | Sélecteurs, ouverture, remplacement et enregistrement |
| WindowsPropertiesPanel | Fichiers associés, rôles importés, métadonnées et repères |
| WindowsPreferencesPanel | Préférences Général, Bande rythmo et Vidéo |
| WindowsRolesPanel | Choix, gestion et portraits des rôles |
| WindowsProjectMedia | Chargement et déchargement des médias au changement de projet |
| WindowsMedia / WindowsAudioPreparation | Lecture et préparation de l'audio externe |
| WindowsDiagnostics | Marqueurs de lancement utilisés par les contrôles CI |

TimelineScrollRange partage les bornes et la taille de vue entre la barre WinUI
et le NSScroller du Mac (TimelineScroller).

Le champ natif traite Unicode, les accents, AltGr et le presse-papiers ; la bande
dessine le texte étiré. Les événements de sélection ne doivent pas réinjecter un
ancien texte du modèle pendant une frappe. Les références Swift conservées par les
callbacks restent nécessaires même lorsque WinUI conserve le contrôle natif.

## Documents et préférences

Chaque fenêtre principale édite un seul projet. La demande Enregistrer / Ne pas
enregistrer / Annuler précède tout remplacement. Les événements Finder passent
par ExternalFileOpenRouter sur Mac ; Windows traite les arguments de lancement.

Le modèle conserve le XML DetX source pour préserver les informations non exposées
par l'éditeur. En l'absence de cadence déclarée, la lecture utilise 25 i/s.
Les chemins des médias doivent être accessibles sur la machine courante.

Sur Mac, les préférences passent par UserDefaults et AppStorage. Sur Windows,
WindowsSettings écrit les préférences et les proportions des panneaux dans
%APPDATA%/Cappella/preferences.json. Les valeurs de préférence à enregistrer
sont définies une seule fois dans ApplicationPreferences.

Les sauvegardes automatiques sont des copies de récupération ; elles ne remplacent
pas le document source. Leurs emplacements sont définis dans ProjectSession sur
Mac et WindowsDocument sur Windows.

## Limites connues

La présence d'une fonction dans le code ne certifie pas sa fidélité métier.
Les exports doivent être relus dans le Cappella d'origine sur des copies.

- Compatibilité avec d'autres variantes DetX et avec les anciens fichiers .det à vérifier.
- Lecture inverse réalisée par recherches d'images ; pas de restitution audio inversée.
- Rendu typographique, codecs et synchronisation à comparer avec les médias réels.
- Protocole Orphée/FTDI, sous-titrage UER et impression d'origine à compléter.
- Les interfaces ne proposent pas encore exactement les mêmes fonctions :
  voir les limites propres à [Windows](WINDOWS.md).
- Les archives ne disposent pas de notarisation Apple ni de signature commerciale Windows.

Les [contrôles automatisés](SCRIPTS.md) vérifient le modèle, la saisie native et
l'ouverture des fenêtres. Ils ne remplacent pas une validation en séance.
