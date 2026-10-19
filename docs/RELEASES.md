# Créer une release GitHub

La convention des fichiers est :

    Cappella-VERSION-OS-ARCH-TYPE.extension

OS vaut macOS ou Windows, ARCH vaut x64 ou arm64, et TYPE vaut Portable ou Setup.
Les archives portables contiennent le dossier de l'application ; les Setup Windows
sont des installateurs. macOS est distribué sous forme d'un ZIP contenant Cappella.app.

## Les cinq téléchargements

Pour le tag v0.9.0-beta.2, la release contient :

- Cappella-0.9.0-beta.2-macOS-arm64-Portable.zip
- Cappella-0.9.0-beta.2-Windows-x64-Portable.zip
- Cappella-0.9.0-beta.2-Windows-x64-Setup.exe
- Cappella-0.9.0-beta.2-Windows-arm64-Portable.zip
- Cappella-0.9.0-beta.2-Windows-arm64-Setup.exe

SHA256SUMS.txt contient les empreintes des cinq fichiers.

## Publier

1. Enregistrer les modifications du projet dans Git, puis les pousser.
2. Depuis le dépôt, créer et pousser un nouveau tag :

   ~~~powershell
   git tag v0.9.0-beta.2
   git push origin v0.9.0-beta.2
   ~~~

   Choisir un numéro encore inutilisé. Le tag détermine la version des noms de
   fichiers ; ne pas réutiliser ni déplacer un tag déjà publié.

3. Attendre la réussite de **Actions → Prepare GitHub release**. Il compile
   macOS ARM64, Windows x64 et Windows ARM64, puis exécute les vérifications
   existantes. Windows ARM64 utilise un runner Windows ARM64 natif.
4. Ouvrir **Releases**, puis le brouillon créé automatiquement. Vérifier les notes
   et les cinq téléchargements. Pour une bêta, cocher **Set as a pre-release**,
   puis cliquer **Publish release**.

Aucun brouillon n'est créé si une compilation ou une vérification échoue.
Le dépôt n'a pas besoin d'un jeton personnel pour publier ce brouillon :
le workflow utilise le jeton GitHub Actions avec contents: write.

## Télécharger sans publier

Lancer le workflow Mac ou Windows depuis **Actions → Run workflow**.
La matrice Windows produit les deux architectures. Chaque téléchargement est
dans un artefact distinct :

| Artefact Actions | Contenu |
|---|---|
| Cappella-macOS-arm64-Portable | Un ZIP macOS ARM64 |
| Cappella-Windows-x64-Portable | Un ZIP Windows x64 |
| Cappella-Windows-x64-Setup | Un Setup Windows x64 |
| Cappella-Windows-arm64-Portable | Un ZIP Windows ARM64 |
| Cappella-Windows-arm64-Setup | Un Setup Windows ARM64 |

GitHub enveloppe chaque artefact dans un ZIP lors du téléchargement depuis
Actions. Le Setup et le portable ne sont jamais regroupés dans le même artefact.
Sur la page Releases, les cinq fichiers sont directement accessibles séparément.

Hors tag, la version des fichiers vient de packaging/Info.plist
(CFBundleShortVersionString). En local, les scripts acceptent aussi une version
explicite : -Version pour Windows, premier argument de build-macos.sh pour Mac.
Cette convention de fichiers ne modifie pas les textes de version dans l'interface.

Les portables Windows nécessitent le Windows App Runtime de leur architecture.
Chaque Setup inclut l'installateur Microsoft correspondant. La désinstallation
conserve le runtime partagé et les préférences.

La signature Apple reste ad hoc ; Windows n'a pas de certificat éditeur.
Une release GitHub n'ajoute ni notarisation Apple ni signature Authenticode.
