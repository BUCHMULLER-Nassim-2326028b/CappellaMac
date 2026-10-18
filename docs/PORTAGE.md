# Périmètre de parité Cappella 3.7

La cible reste le logiciel Windows complet. La version 0.2.0 est une étape
de réécriture native ; elle ne certifie ni une équivalence 1:1 ni une
recompilation des sources d'origine, qui ne sont pas disponibles.

## Références exploitées

- Exécutable Windows PE32 x86, MFC/ATL, Direct3D 9, WinMM, Xerces et FTDI.
- [152 entrées de menus extraites](windows-menu-inventory.json), sous-menus compris.
- Notes de version et ressources locales, dont la mire.
- Deux captures de l'espace de travail, vide puis chargé, fournies par l'utilisateur.
- Audit historique du DetX : 23 rôles, 19 portraits, 402 phrases, 22 boucles,
  139 plans, quatre pistes, 804 signes. Le fichier était à 10 heures d'origine.

Les noms XML de signes `in_open`, `out_open`, `in_close`, `out_close`, `mpb`,
`fvr`, `weuque`, `neutral`, ainsi que `voice`, `off`, `bookmark` et `label`,
figurent dans les chaînes du binaire. La présence de ces chaînes renseigne sur
le format ; elle ne prouve pas à elle seule toutes ses règles ni la position
exacte des éléments dans le XML. Les nouveaux bookmarks sont écrits sous la
racine et doivent notamment être testés dans le logiciel Windows.

## État de l'implémentation 0.2.0

| Domaine | Code écrit | À reproduire ou à vérifier |
|---|---|---|
| Espace de travail | Script monospace à gauche, image à droite, cartouche sous le script, quatre pistes en bas | Comparaison visuelle sur Mac ; police exacte Windows ; comportement précis des séparateurs |
| Documents | Lecture/écriture DetX et format de travail natif | Autres versions et `.det`, récupération/rotation des sauvegardes, validation par réouverture Windows |
| Dialogues | Texte, rôle, piste, bornes, voix off | Réactions avancées et attributs complexes à comparer ; édition directe dans la bande |
| Signes | Séquences texte/signes, signes intermédiaires, ancrage dans le texte, insertion/déplacement/suppression | Voyelles A/I/O, détachement de liens, placement et géométrie exacts de chaque symbole |
| Rythmo | Texte étiré entre ancrages, curseur central, rôles sur noir, ouvertures vertes et fermetures rouges | Identité typographique et synchronisation perceptuelle ; réglages fins de grille |
| Rôles | Nom/couleur/portrait/genre/description ; import sélectif depuis un DetX | Autres formats de liste, collisions à vérifier sur fichiers réels |
| Propriétés | Titres, épisode, production, détecteur, auteurs, notes et résumé | Mise en page des fenêtres et règles métier originales |
| Navigation | Phrases, rôle, signes, boucles, plans, timecode et positions | Comportements limites ; import/export des bookmarks à vérifier dans Windows |
| Boucles et plans | Ajout, suppression, modification, renumérotation des boucles lors de l'ajout | Détection automatique des plans et règles de renumérotation originales |
| Transport | Horloge sans vidéo, lecture/pause, pas image, vitesses de shuttle | Lecture inverse par recherche d'images à mesurer ; précision réelle avec différents codecs |
| Audio | VI externe, alternance VO/VI, volume et sourdine | Enregistrement, routage, compensation et traitement des erreurs complexes |
| Projection | Fenêtre indépendante, lecteur vidéo séparé et suivi de position | Deux écrans réels ; offset ; précision mesurée, notamment au changement de vitesse |
| Recherche | Texte, rôle, casse et mots entiers | Comparaison des règles exactes et navigation des résultats |
| Vérification | Structure, références de rôle, bornes, signes ordonnés, phrases vides et chevauchements | Ensemble des diagnostics métier de Cappella et correction interactive |
| Exports | Script RTF et croisillé CSV | Formatage exact du script/croisillé original, impression et sous-titrage UER |
| Matériel | Aucune intégration | Protocole Orphée/FTDI et équipements à identifier/tester |
| Livraison | `.app` ARM64, tests modèle, lancement sur macOS 15/26 et aperçus prévus | Exécution de la nouvelle CI ; signature Developer ID et notarisation |

## Validation

Le démarrage de la version 0.1.1 a été confirmé par l'utilisateur. Les changements
0.2.0 n'ont pas été compilés ni exécutés depuis le poste Windows de développement.
Ils doivent passer le workflow avant toute conclusion sur le rendu et les fonctions.

Les nouveaux tests Swift couvrent notamment la conservation des segments lipsync,
les changements de texte/bornes, les déplacements, les décalages atomiques, le XML
non exposé, les métadonnées, les portraits et les retours à la ligne Unicode.
La CI ouvre aussi un DetX synthétique pour exercer le rendu peuplé.

Les exports doivent être relus dans le logiciel Windows et comparés sur des copies.
Le fichier DetX privé initial n'est plus disponible à son chemin de Téléchargements
dans l'environnement actuel. Son audit est conservé ; le test local peut être relancé
sur Mac avec `CAPPELLA_DETX_PATH` lorsqu'une copie du fichier est accessible.

Une capture seule ne décrit pas les interactions ni toutes les fonctions. Les
éléments encore incertains doivent être observés et testés sur l'application Windows.
