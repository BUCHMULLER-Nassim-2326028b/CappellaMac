# Créer une release GitHub

Les workflows `Native macOS ARM64` et `Native Windows (Swift-WinRT)` compilent et testent chaque plateforme. Le workflow `Prepare GitHub release` les lance ensemble lorsqu’un tag commençant par `v` est poussé. Il crée ensuite un **brouillon**, avec les deux ZIP, le Setup Windows et leurs sommes SHA-256. Aucun brouillon n’est créé si un build ou un test échoue.

1. Enregistrer les changements dans Git et les pousser sur GitHub.
2. Depuis le dossier du dépôt, créer un nouveau tag pour ce commit :

   ```powershell
   git tag v0.9.0-beta.1
   git push origin v0.9.0-beta.1
   ```

   Choisir un autre numéro si ce tag existe déjà. Ne pas réutiliser ni déplacer un tag publié.

3. Dans **Actions → Prepare GitHub release**, attendre la réussite des jobs Mac, Windows et release.
4. Ouvrir **Releases**, éditer le brouillon, vérifier les notes et les trois téléchargements, puis cliquer **Publish release**. Pour une bêta, cocher **Set as a pre-release**.

Pour tester sans release : **Actions → Native Windows (Swift-WinRT) → Run workflow**, puis télécharger l’artefact `Cappella-Windows-x64` en bas de l’exécution. Les artefacts Actions ont une durée de rétention ; les fichiers joints à une release sont destinés à la distribution.

Fichiers attendus : `Cappella-MacOS-arm64.zip`, `Cappella-Windows-x64.zip` et `Cappella-VERSION-Windows-x64-Setup.exe`. La version affichée dans l’application macOS reste définie dans `packaging/Info.plist` : la mettre à jour avant de créer le tag si nécessaire.

La signature Apple est actuellement ad hoc ; Windows n’a pas de certificat de signature commerciale. Une release GitHub n’ajoute ni notarisation Apple ni signature Authenticode.
