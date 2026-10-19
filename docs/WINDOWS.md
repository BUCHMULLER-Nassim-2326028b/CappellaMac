# Cappella Windows

L'application utilise WinUI 3 depuis Swift avec Swift-WinRT. Le moteur CappellaCore
est partagé avec le Mac ; SwiftUI et AppKit restent propres à macOS.

## Lancer l'archive

Windows x64 avec Windows App Runtime 1.7. Extraire tout le ZIP et conserver les DLL,
Resources et Licenses auprès de Cappella.exe. Les DLL Swift sont incluses dans
l'archive ; Windows App Runtime 1.7 x64 doit être installé séparément
([téléchargements Microsoft](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads-archive)).
Le script windows/Installer-runtime.ps1 reste dans le dépôt pour le développement
et la CI. Ce script et la documentation ne sont pas ajoutés au ZIP distribué.

## Compiler

Installer Swift pour Windows, Visual Studio 2022 avec les outils C++ et un Windows
SDK. La CI utilise Swift 6.2 ; le développement local utilise aussi Swift 6.4.1.

    .\scripts\build-windows.ps1

Puis, pour réutiliser les projections déjà générées :

    .\scripts\build-windows.ps1 -SkipPrepare

Ajouter -Configuration debug pour un binaire de développement. La configuration
par défaut est release. Résultats : dist/Cappella-Windows-x64/Cappella.exe et
dist/Cappella-Windows-x64.zip.

La préparation peut également être lancée séparément :

    .\scripts\prepare-windows.ps1

Les archives NuGet sont épinglées et vérifiées par SHA-256. Les caches .windows
et .build restent locaux. Une configuration de projections modifiée déclenche
leur régénération même avec -SkipPrepare. Le support manuel WinUI/WinAppSDK est
resynchronisé avant compilation sans régénérer les projections.

Les [scripts et contrôles CI](SCRIPTS.md) et le [guide de release](RELEASES.md)
décrivent les autres commandes.

## Documents et réglages

Ouvrir remplace le projet courant dans la même fenêtre après confirmation des
modifications non enregistrées. Chaque lancement de l'exécutable peut créer une
instance indépendante. Fermer la fenêtre principale ferme sa projection et termine
cette instance.

Les propriétés regroupent Fichier, Programme, Production, Description et Repères.
La catégorie Fichier relie la vidéo, le son externe et la liste de rôles à importer.
Les changements sont validés par OK ou Appliquer.

Les préférences Général, Bande rythmo et Vidéo sont stockées dans
%APPDATA%/Cappella/preferences.json, avec les proportions des panneaux.
La sauvegarde automatique est désactivable et son intervalle est réglable.
Ses copies de récupération sont stockées dans le dossier de données utilisateur
Cappella/Autosaves, séparément du fichier original.

## Audio et limites

Le fichier audio externe remplace le son de la vidéo. Les AIFF/AIFC PCM pris en
charge sont préparés en WAV ; quatre canaux sont séparés en deux paires stéréo VO
et VI. Les fichiers source restent inchangés. Les dispositions de quatre flux mono
et les formats compressés AIFC ne sont pas équivalents au moteur Mac.

L'enregistrement microphone et la détection automatique des plans restent propres
au Mac. La projection Windows affiche la vidéo ; elle ne reproduit pas encore
l'ensemble de l'écran de contrôle Mac. La recherche et certains outils avancés
restent moins complets sur Windows.

Les dialogues internes suivent le thème de l'application ; les sélecteurs de
fichiers Windows conservent le thème système. La validation des codecs, de la
fluidité et des commutations VO/VI nécessite des médias réels.
