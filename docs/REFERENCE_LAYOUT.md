# Référence visuelle Cappella Windows

La cible est la disposition des deux captures fournies, avec les adaptations
nécessaires à macOS (barre de menus globale, boutons natifs de fenêtre).

- Le script occupe la partie gauche (environ 44 % dans la capture chargée).
  Le séparateur vertical est redimensionnable.
- Le script est un papier gris très clair, avec petits timecodes et dialogues
  monospace. La saisie d'une phrase s'ouvre au double-clic ; les réglages de
  programme et rôles sont dans des fenêtres de dialogue.
- L'image est à droite. Sans vidéo attachée, c'est le fichier `Mire.jpg` fourni
  avec le programme Windows, désormais embarqué dans le `.app`.
- Le cartouche fait environ 92 points sous le script : timecode, numéro de boucle,
  durée, bornes et indicateur VO/VI sur fond ardoise. Il ne contient pas une barre
  de transport ajoutée au prototype.
- La rythmo fait environ 146 points sur toute la largeur, en quatre pistes.
  Le curseur rouge est centré ; les noms des rôles sont sur des étiquettes noires.
  Les débuts et fins de phrase ont des repères verts et rouges.
- Le texte est étiré horizontalement entre les signes de synchronisation,
  plutôt que simplement affiché à sa taille naturelle au début d'une phrase.
- La police cursive est pour l'instant `Apple Chancery`, modifiable dans les
  préférences. La police exacte du rendu Windows n'a pas été identifiée.

La correspondance des proportions, caractères, marges et comportements doit être
contrôlée avec les captures macOS. Elle n'est pas certifiée pixel pour pixel.
Les points SwiftUI et les pixels Windows ne sont pas des unités équivalentes.

Le workflow tente de produire deux captures par système dans les artefacts
`CappellaMac-previews-macos-15` et `CappellaMac-previews-macos-26` : éditeur vide,
puis petite scène DetX synthétique à trois pistes et signe intermédiaire. La scène
sert uniquement de test ; elle ne contient pas le fichier privé de l'utilisateur.
