# Raccourcis clavier

Référence : le document Raccourcis.pdf fourni pour Cappella. Ce relevé compare
le PDF (y compris les schémas du pavé numérique) avec les gestionnaires Mac et Windows ; il ne constitue pas une validation
interactive. Les touches sans modificateur sont réservées à la détection :
pendant la saisie, les lettres, l'espace et les commandes de texte restent
traités par le champ natif. Les raccourcis explicites de phrase restent actifs.

Ctrl+U bascule le statut voix off / hors champ de la phrase sélectionnée.
Toute la réplique est alors soulignée, y compris pendant son édition et dans
la projection Mac. Le statut est enregistré dans DetX et .cappellaproject ;
une seconde pression retire le statut et le soulignement.

## Fichiers et outils

| Raccourci du PDF | Action | État |
|---|---|---|
| Ctrl+N / Ctrl+O | Nouveau / ouvrir | Implémenté |
| Ctrl+S / Ctrl+Maj+S / Ctrl+Alt+S | Enregistrer / sous / une copie | Implémenté |
| Ctrl+P | Propriétés | Implémenté |
| Ctrl+Maj+V | Ouvrir l'image vidéo | Implémenté |
| Ctrl+E | Exporter script et croisillé | Partiel : le raccourci ouvre l'export du script ; le croisillé a sa propre commande dans Fichier |
| Ctrl+Maj+E | Exporter les sous-titres | Manquant : export sous-titres non porté |
| Ctrl+R | Rôles | Implémenté |
| Ctrl+F | Rechercher | Implémenté ; options Windows moins complètes |
| F4 | Vérifier la rythmo | Implémenté ; couverture métier à compléter |
| Ctrl+U | Voix off / hors champ, soulignement | Implémenté |
| F1 | Documentation | Implémenté |

## Navigation, pistes et lecture

| Raccourci du PDF | Action |
|---|---|
| Haut / Bas | Lecture avant / arrière ; une seconde pression met en pause |
| Espace | Lecture / pause supplémentaire |
| Alt+Gauche / Alt+Droite | Image précédente / suivante |
| Gauche / Droite | Signe précédent / suivant |
| F9 / F10 | Phrase précédente / suivante |
| Ctrl+F9 / Ctrl+F10 | Phrase précédente / suivante du rôle courant |
| Tab / Maj+Tab | Alias de navigation entre phrases |
| F11 / F12 | Boucle précédente / suivante |
| Ctrl+G | Aller au timecode |
| V / B | Lecture arrière ×¾ / ×¼ |
| N / virgule | Lecture avant ×¼ / ×¾ |
| Ctrl+Haut / Ctrl+Bas | Piste précédente / suivante |
| F5 à F8 | Sélectionner une piste |
| Ctrl+F5 à Ctrl+F8 | Déplacer la phrase vers une piste |

Ces commandes sont raccordées sur Mac et Windows. La lecture inverse reste une
navigation par recherches d'images et ne restitue pas l'audio à l'envers.

## Affichage et audio

| Raccourci du PDF | Action |
|---|---|
| Alt+Entrée | Plein écran |
| + / - | Zoom de la bande rythmo |
| Ctrl+Alt+F9 | Afficher/masquer la détection / le script |
| Ctrl+Alt+F10 | Afficher/masquer grille et signes |
| Ctrl++ / Ctrl+- | Monter / baisser le volume |
| Ctrl+* | Couper / rétablir le son |
| F2 | Basculer VO / VI |

Sur Windows, les symboles de volume sont reconnus sur le clavier principal comme
sur le pavé numérique. AltGr reste disponible pour la saisie ; les flèches
Ctrl+Alt et les combinaisons F9/F10 sont traitées explicitement.

## Édition, signes et texte

| Raccourci du PDF | Action | État |
|---|---|---|
| Entrée | Mode détection / édition ; valider le texte | Implémenté |
| Échap | Annuler la phrase en cours | Implémenté |
| Suppr, hors saisie | Supprimer le signe interne sélectionné, sinon la phrase | Implémenté ; contexte précis à comparer à l'original |
| Ctrl+Suppr | Supprimer la phrase, y compris pendant la saisie | Implémenté |
| Ctrl+X / Ctrl+C / Ctrl+V | Couper / copier / coller phrase ou texte selon le contexte | Implémenté |
| Ctrl+A | Sélectionner tout le texte en cours d'édition | Traitement natif |
| Ctrl+Entrée | Insérer un retour à la ligne | Implémenté |
| Ctrl+Gauche / Ctrl+Droite | Déplacer un signe en détection | Implémenté ; en saisie, navigation native entre les mots |
| Ctrl+Alt+Gauche / Ctrl+Alt+Droite | Décaler l'accroche du signe d'un caractère | Implémenté pour un signe interne sélectionné |
| Ctrl+Maj+D | Décrocher tous les signes | Implémenté ; fidélité du comportement à vérifier |
| ² / & | Accroche précédente / suivante | Partiel : navigation au point d'accroche ; comportement d'attachement exact à compléter |
| Suppr / Retour arrière en édition | Retirer un caractère / son accroche | Texte traité nativement ; détachement indépendant à comparer au logiciel d'origine |

Pavé numérique : 0 ajoute une boucle, 1 un plan, 2/3 un début/une fin de phrase
ouverts, Ctrl+2/Ctrl+3 les variantes fermées. 4 correspond à m/b/p,
5 à f/v/r, 6 au signe neutre, 7 à A, 8 à O et 9 au cul-de-poule.
Le schéma du PDF et les pictogrammes de la
[documentation officielle](https://cappella.app/documentation13.html) confirment
cette disposition ; seules les touches 2 et 3 ont une variante avec Ctrl.
Les libellés de réaction suivent le PDF fourni, qui diffère de l'ancienne
documentation sur certains textes.

## Réactions

La table est commune aux deux plateformes dans ReactionShortcuts.
Une seconde pression ferme la réaction ouverte ; la préférence de fermeture
automatique reste prioritaire. Les touches de réaction ne remplacent pas
la saisie de texte en mode édition.

| Touche | Texte | Touche | Texte |
|---|---|---|---|
| A | ah | E | (effort) |
| R | (réac) | T | tst |
| U | euh | Maj+U | huh |
| I | (rire) | O | oh |
| Maj+O | OUT | P | (peur) |
| S | sniff | F | fff |
| Maj+F | (_fin) | G | grrr |
| Maj+G | argh! | H | hhh |
| Maj+H | han! | J | (joie) |
| L | (pleurs) | M | mts |
| Maj+M | mmm | X | X |
| ? | (réac ?) | C | (course) |

Sur Mac, les commandes courantes acceptent aussi Cmd. Les raccourcis système,
les sélecteurs de fichiers et les champs des boîtes de dialogue conservent
leurs comportements natifs.
