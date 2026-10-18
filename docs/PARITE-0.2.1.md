# Ajustements de fidélité 0.2.1

Références consultées le 18 octobre 2026 : [documentation complète](https://cappella.app/), chapitres 1 à 8, [raccourcis](https://cappella.app/documentation13.html), [audio et fonctions avancées](https://cappella.app/documentation12.html), et captures Windows fournies par Nassim. Les captures priment lorsque les indications anciennes se contredisent, notamment pour F11/F12.

## Audio

L'image et le fichier Son séparé utilisent désormais un seul AVPlayer et une composition commune. Le fichier Son remplace la bande son de la vidéo ; il ne désigne plus obligatoirement une VI externe. Le routage additionne les canaux des pistes audio dans l'ordre du conteneur : quatre canaux = première paire VO, seconde paire VI ; deux canaux = VO/VI mono. F2 modifie le mix du lecteur courant, sans recherche temporelle ni changement de vitesse. Les fichiers mono et les autres dispositions conservent leur audio normal et ne proposent pas une VI inventée.

Les pistes stéréo séparées sont sélectionnées par AVAudioMix. Un tap MediaToolbox sélectionne les canaux d'une piste PCM décodée multicanal, traite les buffers entrelacés ou planaires, et duplique une version mono sur les deux sorties. Les quatre canaux d'une seule piste sont repliés vers sa première paire avant le mélange de sortie.

À vérifier sur un Mac avec les vrais médias : niveaux exacts du mélange matériel, absence de fuite VO/VI, commutations rapides pendant lecture/recherche. Quatre pistes mono indépendantes sont préparées en deux fichiers CAF stéréo temporaires, en préservant les silences, les positions initiales et les différences de durée. Cette préparation se fait en arrière-plan, utilise des buffers de taille bornée et peut prendre du temps sur un long film. Le cache temporaire est supprimé à la fermeture du document. Un contrôle natif CI compare chaque échantillon des deux versions produites pour détecter inversion gauche/droite, fuite audio et désynchronisation. La lecture arrière reste une recherche d'images et ne restitue pas le son inversé.

## Édition et propriétés

La zone de saisie latérale est supprimée. Entrée ouvre la liste des rôles puis un éditeur natif dans la piste de la bande, avec fond noir, curseur, sélection, accents et presse-papiers. Entrée valide ; Échap annule les changements de la phrase ou supprime la nouvelle phrase provisoire. L'ouverture par le pavé numérique commence en détection ; Entrée passe ensuite à l'écriture. Les limites temporelles déjà repérées ne sont plus toutes étirées lors de la fermeture d'une phrase. L'édition du texte conserve les positions des signes et ajuste seulement leurs offsets concernés.

L'éditeur sur bande reste une zone NSTextView ; l'étirement du texte pendant sa saisie n'est pas encore identique au dessin segmenté du Canvas après validation. Les accroches &/² parcourent actuellement les signes ayant des offsets distincts : le statut « non lié » du format d'origine reste à reproduire plus finement. « Décrocher tous les signes » redistribue les accroches régulièrement ; ce comportement reste une approximation.

Les propriétés comportent Fichier, Programme, Production, Description et Repères. Le premier onglet permet de choisir Image, Son et Liste des rôles. Un brouillon isole les changements jusqu'à OK ou Appliquer ; Annuler préserve le document. Les médias existants et accessibles sont rechargés à l'ouverture ; les anciens chemins Windows doivent être remplacés par leurs chemins Mac.

## Commandes

Les raccourcis de transport, navigation, pistes, déplacement des phrases, signes, accroches, recherche suivante, vérification, réactions et VO/VI sont reliés aux actions de l'éditeur. Ctrl fonctionne comme dans Cappella ; les commandes usuelles acceptent également Cmd. F5–F8 changent la piste active, Ctrl+F5–F8 déplacent la phrase. Les raccourcis de lecture n'interceptent pas les lettres tapées dans le texte. Sur un clavier Apple configuré pour les touches multimédias, maintenir Fn pour envoyer F1–F12 à l'application.

Le copier/couper/coller de phrase conserve les signes, refuse les chevauchements et une boucle traversée, puis demande l'attribution du rôle. Les menus Fichier/Édition sont nommés en français ; View et Window sont retirés. Les fichiers récents restent gérés par le contrôleur de documents. L'application déclare le français dans son bundle et choisit cette langue pour ses dialogues système.

La détection des changements de plan analyse les images décodées en arrière-plan avec un seuil réglable et annulation. Ce nouvel algorithme ne prétend pas reproduire les résultats exacts du logiciel Windows. Audio > Enregistrer enregistre le microphone dans un WAV après sélection du fichier et consentement macOS ; son fonctionnement historique exact n'est pas documenté sur le site. La commande Orphée est visible mais désactivée : le protocole matériel reste à porter. Les options manuelles Désentrelacer et Haute qualité ne sont pas encore reproduites. Les mises à jour ouvrent les versions du dépôt Mac, sans installateur automatique.

## Validation

Quatre nouveaux tests couvrent l'édition autour des accroches, les suppressions, les scalaires Unicode et la séparation des versions audio. Ils complètent les tests existants. La machine de développement Windows ne possède pas Swift/Xcode : les tests natifs et le lancement doivent encore passer dans GitHub Actions sur macOS 15 et 26. Le contrôle de syntaxe éventuel ne remplace pas cette compilation.
