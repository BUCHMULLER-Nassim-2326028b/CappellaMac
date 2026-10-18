# Cappella Mac — réécriture native visant la parité avec Cappella 3.7

Le premier prototype démarre sur Mac Apple Silicon. La version 0.2.0 reprend
la disposition de Cappella Windows et étend l'édition et la synchronisation.
**La parité complète avec le programme d'origine n'est pas encore atteinte.**
Sans les sources C++, il s'agit d'une réécriture Swift fondée sur les fichiers,
ressources et comportements observés, pas d'une recompilation du code original.

## Espace de travail

Script à gauche, vidéo à droite, cartouche sous le script et quatre pistes de
bande rythmo en bas. Sans vidéo, l'image de mire d'origine est affichée.
Le curseur est centré, et le texte est étiré entre les signes de synchronisation.
Voir la [référence visuelle](docs/REFERENCE_LAYOUT.md).

Les réglages passent par les menus : Contrôle, Position, Affichage, Audio,
Rôles, Propriétés, Recherche et Préférences. Double-cliquer sur une phrase pour
modifier son texte, son rôle, sa piste et ses bornes. Glisser un signe dans la
rythmo pour le déplacer. Les raccourcis de navigation ne capturent pas les
espaces ni les flèches pendant la saisie de texte.

Le timecode et la lecture fonctionnent aussi sans vidéo attachée.
La lecture inverse du transport est réalisée par recherche d'images et reste
à mesurer en conditions réelles. La piste VI externe suppose un fichier audio
aligné sur le début du média ; il n'y a pas encore de compensation matérielle.

## Documents et fonctions écrites

- Ouverture/enregistrement de `.detx` directement depuis le menu Fichier.
- Format de travail `.cappellaproject`, avec XML source conservé.
- Dialogues à plusieurs séquences texte/lipsync ; préservation des types importés.
- Création et déplacement des signes d'ouverture/fermeture, MPB, FVR, neutre et weuque.
- Rôles, couleurs, portraits, descriptions, genre ; propriétés du programme et de production.
- Navigation par phrase, rôle, signe, boucle et plan ; ajout de boucles et plans.
- Recherche par rôle, casse et mots entiers ; vérification des bornes et chevauchements.
- Décalage de la rythmo et changement du timestamp avec déplacement cohérent des signes.
- Positions mémorisées ; script RTF et croisillé CSV.
- Volume, sourdine, alternance VO/VI et fenêtre de contrôle indépendante.

Cette liste décrit l'implémentation, pas une certification de comportement 1:1.
Voir [PORTAGE.md](docs/PORTAGE.md) pour les limites, notamment sous-titres UER,
enregistrement, matériel Orphée/FTDI et fidélité exacte du rendu.

Le fichier DetX fourni ne déclare pas sa cadence. L'ouverture utilise 25 i/s par
défaut ; ce choix doit être confirmé avec le média. Le fichier vidéo doit être
relié manuellement : un chemin Windows n'est pas une URL macOS.

## Compiler

Sur un Mac Apple Silicon sous macOS 13 ou plus, avec Xcode installé et ouvert
une fois, lancer à la racine :

```sh
swift test --arch arm64
bash scripts/build-macos.sh
open "dist/Cappella Mac.app"
```

Le script produit `dist/Cappella Mac.app` et `dist/CappellaMac-arm64.zip`.
La signature est ad hoc ; la notarisation et la signature Developer ID ne sont
pas configurées.

Depuis Windows, pousser les sources sur GitHub déclenche le workflow
`Native macOS ARM64`. Il compile et teste sur macOS 15, puis ouvre le même binaire
sur macOS 26. Les tests de lancement exigent que l'éditeur apparaisse, avec et
sans DetX. Des aperçus PNG sont proposés si la capture d'écran du runner est autorisée.
Télécharger l'artefact `CappellaMac-arm64` après réussite des deux jobs.

## Validation

La version 0.1.1 a été confirmée comme fonctionnant par l'utilisateur.
Les nouvelles modifications 0.2.0 doivent encore passer les tests et la comparaison
visuelle sur Mac. Les tests Swift ne sont pas exécutables sur le poste Windows actuel.

Pour tester un vrai fichier local sur Mac sans le publier :

```sh
CAPPELLA_DETX_PATH="/chemin/exemple.detx" swift test --arch arm64
```

L'export doit être vérifié dans Cappella Windows sur une copie, en particulier
pour les signes, les positions mémorisées et les attributs de voix off.

`assets/` contient l'installation Windows et reste ignoré par Git. La mire est
copiée dans `packaging/Resources/` pour être incluse dans l'application native.
Le logiciel natif ne charge ni l'exécutable Windows ni ses DLL.
