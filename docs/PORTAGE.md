# Périmètre de parité Cappella 3.7

## Éléments vérifiés sur les fichiers fournis

`assets/Cappella.exe` est un exécutable PE32 x86 (machine `0x014c`), sans répertoire CLR.
Les chaînes internes indiquent MFC/ATL et un projet Visual Studio 2005.
Les imports incluent Direct3D 9, `d3dx9_42.dll`, WinMM, GDI/GDI+, COM,
`xerces-c_2_8.dll`, WinINet et `FTD2XX.dll`.
La présence d'une DLL FTDI indique une dépendance matérielle possible ; le protocole
et les équipements réellement nécessaires ne sont pas encore établis.

Les ressources de menus de l'exécutable ont été lues sans le lancer.
L'[inventaire des 152 entrées de menu](windows-menu-inventory.json) inclut les sous-menus
et menus contextuels ; il ne signifie pas 152 fonctions distinctes.
Cet inventaire sert de référence de parité avec les notes de version locales.

Le DetX fourni comporte 23 rôles, 19 portraits, 402 phrases, 22 boucles, 139 plans,
804 lipsync et quatre pistes (0 à 3). Toutes les phrases observées ont la forme
`lipsync(in_open), text, lipsync(out_open)`.
L'origine média est `10:00:00:00`.
La cadence de 25 i/s est une hypothèse compatible avec les timecodes observés,
pas une valeur explicitement déclarée par le document.

## Implémentation et travail restant

| Domaine | État du code natif | Travail pour la parité |
|---|---|---|
| Documents | Format propre, XML original conservé, import/export du profil observé | Autres profils DetX/DET, fichiers récents, copies, récupération et sauvegardes spécifiques |
| Rôles | Noms, couleurs, création et suppression | Portraits et descriptions éditables, genre, import sélectif, règles de validation |
| Programme | Titre et auteur éditables, autres métadonnées conservées | Éditeur complet des propriétés, épisodes, production, second auteur, résumé |
| Dialogues | Édition texte, rôle, piste, début/fin, recherche | Signes intercalaires, voix off, modes édition/détection, détachement des signes |
| Timecode | Entiers 24/25/30 i/s, origine média | Cadences rationnelles, drop-frame si nécessaire, changement d'origine contrôlé |
| Rythmo | Défilement élémentaire, pistes conservées | Étirement du texte, police/géométrie originale, signes, curseur d'édition et détection |
| Boucles et plans | Lecture/conservation et accès aux boucles | Création/édition, renumérotation, navigation complète, détection automatique des plans |
| Transport | Lecture/pause, recherche, pas d'une image | Lecture inverse, jog, shuttle multi-vitesses et validation de la précision image |
| Audio | Audio du média AVPlayer | VI/VO séparées, synchronisation, enregistrement et routage |
| Projection | Prévisualisation dans une feuille | Fenêtre indépendante, second écran, plein écran et offset de contrôle |
| Exports | DetX du profil observé | Script, croisillé, sous-titres UER, impression et validation des formats |
| Contrôle qualité | Validation structurelle à l'ouverture/enregistrement | Vérification métier interactive et correction des erreurs |
| Intégrations | Aucune | Machine Orphée/FTDI, protocole et matériel à identifier |
| Préférences | Aucune interface dédiée | Raccourcis, options d'édition et rendu, positions mémorisées |
| Livraison | Script `.app` et CI écrits | Compilation réelle, tests interface, stabilité, signature et notarisation |

## Validation requise avant utilisation réelle

1. Compiler l'interface et exécuter les tests sur macOS ARM64.
2. Exécuter les tests Swift sur le DetX fourni via `CAPPELLA_DETX_PATH`.
3. Réouvrir un export sur Cappella Windows et comparer rôles, timecodes, portraits,
   textes, signes, pistes, boucles, plans et propriétés.
4. Tester une vidéo réelle à la bonne cadence, avec navigation image par image,
   origine à dix heures et synchronisation du son.
5. Étudier des fichiers contenant les autres signes et des phrases à plusieurs segments.
6. Comparer chaque famille de commandes de l'inventaire Windows sur des cas reproductibles.

Sans les sources ni une spécification complète, le fichier d'exemple et les ressources
du binaire permettent d'établir une partie du comportement. Ils ne suffisent pas
à certifier une équivalence complète, notamment matérielle.
