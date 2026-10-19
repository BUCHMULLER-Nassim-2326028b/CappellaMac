import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func preferences() async {
        var draft = self.document.preferences
        func check(_ title: String, _ value: Bool) -> CheckBox {
            let caption = label(title); caption.textWrapping = .wrap
            let view = CheckBox(); view.content = caption; view.isChecked = value
            return view
        }
        let theme = ComboBox(); theme.items.append("Clair"); theme.items.append("Sombre"); theme.selectedIndex = dark ? 1 : 0
        let updates = check("Vérifier les mises à jour au lancement", draft.checkUpdates)
        let prefix = check("Préfixer les copies enregistrées par « Copie de »", draft.prefixCopies)
        let automatic = check("Activer la sauvegarde automatique", draft.automaticSave)
        let interval = textField(String(draft.saveInterval)); interval.isEnabled = draft.automaticSave
        automatic.checked.addHandler { _, _ in interval.isEnabled = true }
        automatic.unchecked.addHandler { _, _ in interval.isEnabled = false }
        let general = stack([
            dialogSection("Application", [updates, prefix, dialogField("Apparence", theme)]),
            dialogSection("Sauvegarde automatique", [
                automatic, dialogField("Intervalle (minutes)", interval),
                dialogHint("Les copies de récupération ne remplacent pas votre fichier de travail.")
            ])
        ], spacing: 20)
        let closeReactions = check("Fermer automatiquement les réacs", draft.closeReactions)
        let font = textField(fontFamily), size = textField(String(Int(draft.fontSize)))
        let speed = textField(String(Int(draft.pixelsPerSecond))), height = textField(String(Int(draft.bandHeight)))
        let grid = check("Grille et signes", draft.showGrid), detection = check("Détection", draft.showDetection)
        let band = stack([
            dialogSection("Écriture", [closeReactions, dialogField("Police", font)]),
            dialogSection("Dimensions", [
                dialogColumns([dialogField("Taille des répliques", size), dialogField("Pixels par seconde", speed)]),
                dialogField("Hauteur de la bande", height)
            ]),
            dialogSection("Affichage", [grid, detection])
        ], spacing: 20)
        let control = check("Afficher l'écran de contrôle au lancement", draft.showControlAtLaunch)
        let offset = textField(String(Int(draft.videoOffsetMilliseconds)))
        let reset = button("Réinitialiser le décalage") { offset.text = "0" }
        reset.horizontalAlignment = .left
        let video = stack([
            control,
            dialogSection("Synchronisation", [
                dialogField("Décalage de l'image par rapport au son (ms)", offset),
                dialogHint("Négatif : en retard · Positif : en avance"), reset
            ])
        ], spacing: 20)
        let categories = dialogCategories([("Général", general), ("Bande rythmo", band), ("Vidéo", video)])
        let errorText = dialogError()
        func apply() -> Bool {
            guard let minutes = Int(interval.text), (1...120).contains(minutes),
                  let fontSize = Double(size.text), fontSize.isFinite, (16...42).contains(fontSize),
                  let pixels = Double(speed.text), pixels.isFinite, (15...800).contains(pixels),
                  let bandHeight = Double(height.text), bandHeight.isFinite, bandHeight >= 120,
                  let delay = Double(offset.text), delay.isFinite, (-1000...1000).contains(delay),
                  !font.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorText.text = "Vérifiez les valeurs : intervalle 1–120 min, taille 16–42, échelle 15–800 px/s, hauteur ≥ 120 px, décalage ±1000 ms."
                return false
            }
            draft.appearance = theme.selectedIndex == 1 ? "dark" : "light"
            draft.checkUpdates = updates.isChecked ?? false; draft.prefixCopies = prefix.isChecked ?? true
            draft.automaticSave = automatic.isChecked ?? false; draft.saveInterval = minutes
            draft.closeReactions = closeReactions.isChecked ?? false
            draft.fontName = font.text; draft.fontSize = fontSize; draft.pixelsPerSecond = pixels
            draft.bandHeight = min(max(120, root.actualHeight - 190), bandHeight)
            draft.showGrid = grid.isChecked ?? true; draft.showDetection = detection.isChecked ?? true
            draft.showControlAtLaunch = control.isChecked ?? false; draft.videoOffsetMilliseconds = delay
            guard draft.save() else {
                errorText.text = "Impossible d'enregistrer les préférences dans " + WindowsSettings.fileURL.path
                return false
            }
            self.document.preferences = draft
            media.videoOffset = delay / 1000
            media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
            refresh(); return true
        }
        _ = await dialog("Préférences", content: stack([categories, errorText]), primary: "OK", close: "Annuler",
                         validatePrimary: apply, contentWidth: categories.width)
    }
}
