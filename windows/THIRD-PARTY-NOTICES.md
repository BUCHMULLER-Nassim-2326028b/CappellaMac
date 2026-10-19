# Composants Windows

L’interface utilise WinUI 3 au travers des projections produites par **Swift-WinRT 0.6.0** (The Browser Company, BSD 3-Clause).
Les fichiers de support de SwiftApplication et WindowsAppRuntimeInitializer proviennent de swift-winui / swift-windowsappsdk, adaptés pour Cappella ; leur licence figure dans chaque fichier et dans LICENSE-SwiftWinRT.txt.

Métadonnées et runtime Microsoft : Windows App SDK 1.7.250909003, Windows SDK Contracts 10.0.22621.3233 et WebView2 1.0.2903.40. Leurs licences NuGet sont copiées avec la distribution. Le runtime Swift est redistribué avec sa licence Apache 2.0 avec exception de bibliothèque runtime.

Le générateur et les bibliothèques Microsoft ne sont pas modifiés. Les projections ne sont pas conservées dans Git ; scripts/prepare-windows.ps1 les régénère à partir des archives vérifiées par SHA-256.
