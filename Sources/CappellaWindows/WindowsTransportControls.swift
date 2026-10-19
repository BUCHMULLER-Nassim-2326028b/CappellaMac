import Foundation
import CappellaCore
import WinUI

extension WindowsEditor {
    func changeTimestamp() async {
        guard !dialogShowing, !isClosed else { return }
        media.stop(); self.document.finishEditing(); updateTextEditor()
        let input = textField(Timecode.format(self.document.project.mediaStartFrame, fps: fps))
        let explanation = label("Les phrases, signes, boucles et plans sont décalés avec l'origine vidéo.")
        explanation.textWrapping = .wrap
        let message = label(""); message.textWrapping = .wrap
        let content = stack([label("Timestamp de l'image"), input, explanation, message])
        content.width = 400
        content.loaded.addHandler { _, _ in _ = try? input.focus(.programmatic); try? input.selectAll() }
        _ = await dialog("Changer le timestamp", content: content, primary: "Appliquer", close: "Annuler", validatePrimary: {
            guard let origin = Timecode.parse(input.text, fps: self.fps) else {
                message.text = "Timecode invalide : HH:MM:SS:II."
                return false
            }
            let delta = origin - self.document.project.mediaStartFrame
            let position = self.document.frame + delta
            do {
                try self.document.commit { try $0.shift(by: delta, includingMediaOrigin: true) }
                self.seek(position)
                return true
            } catch {
                message.text = error.localizedDescription
                return false
            }
        }, contentWidth: 400, defaultButton: .primary)
    }
}
