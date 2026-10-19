# Cappella Windows — Swift-WinRT / WinUI 3

L’application Windows utilise **les contrôles natifs WinUI 3**, projetés en Swift avec [Swift-WinRT](https://github.com/thebrowsercompany/swift-winrt). Le moteur `CappellaCore` (DetX, signes, timing, données et règles d’édition) est partagé avec macOS. SwiftUI et AppKit restent propres au Mac.

## Lancer l’archive

Windows 10 version 1903 ou ultérieure, x64. Extraire **tout** le ZIP, conserver les DLL et le dossier `Resources` près de `Cappella.exe`. Installer une fois Windows App Runtime 1.7 x64 avec le script `Installer-runtime.ps1` fourni (clic droit → Exécuter avec PowerShell), puis ouvrir `Cappella.exe`. Les DLL Swift sont incluses ; le compilateur n’est pas nécessaire pour utiliser le logiciel.

## Compiler

Installer Swift pour Windows, Visual Studio 2022 avec les outils C++ et un Windows SDK. Le portage a été compilé localement avec Swift 6.4.1 ; le workflow utilise Swift 6.2, comme les projections amont.

```powershell
./scripts/prepare-windows.ps1
swift test -c release -j 4
./scripts/build-windows.ps1 -SkipPrepare
./scripts/smoke-windows.ps1 -Executable dist/Cappella-Windows-x64/Cappella.exe -Fixture Tests/Fixtures/layout.detx
```

La première compilation des projections prend plusieurs minutes. Les archives NuGet sont épinglées et vérifiées par SHA-256. `.windows/` et `.build/` sont des caches locaux ignorés par Git. Pour exécuter uniquement les tests du moteur sans installer WinUI, lancer `swift test` avant de préparer les projections.

Résultat : `dist/Cappella-Windows-x64.zip`. Pour les releases GitHub : [RELEASES.md](RELEASES.md).

## Périmètre actuel

Instances indépendantes, ouverture depuis l’Explorateur, ouverture/enregistrement DetX et projets JSON, confirmation des changements non enregistrés, quatre pistes de rythmo, édition directe au clic simple, signes/boucles/plans, navigation clavier, menus français, rôles et portraits, presse-papiers de phrases, export texte/CSV, thèmes clair/sombre et sauvegardes automatiques désactivables. Les sauvegardes de récupération sont séparées du fichier source, dans le dossier de données utilisateur `Cappella/Autosaves`.

Cette première version Windows doit encore passer les essais métier sur les médias réels. Le lecteur actuel sélectionne des flux audio séparés pour VO/VI ; le routage des canaux d’un flux PCM à quatre canaux et la combinaison de quatre flux mono ne sont pas encore équivalents au moteur Mac. La fenêtre de projection affiche pour l’instant la vidéo. L’enregistrement audio, la détection automatique des plans, certaines préférences vidéo restent à porter. Ne pas utiliser cette version comme remplacement validé du Mac en séance.


Chaque lancement ouvre une instance indépendante. Fichier > Ouvrir remplace le projet de la fenêtre actuelle avec la demande d'enregistrement habituelle. Fermer la fenêtre principale ferme aussi l'écran de contrôle et termine cette instance. Sur Mac, plusieurs processus indépendants restent possibles ; fermer la dernière fenêtre quitte l'application.
