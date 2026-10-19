import Foundation
import CappellaCore
import UWP
import WinUI
import WindowsFoundation

extension WindowsEditor {
    func find() async {
        guard !dialogShowing, !isClosed else { return }
        media.stop()
        self.document.finishEditing(); updateTextEditor()
        if let id = search.roleID, !self.document.project.roles.contains(where: { $0.id == id }) { search.roleID = nil }
        let input = textField(search.text, placeholder: "Texte à rechercher")
        input.header = "Rechercher"; input.minWidth = 0
        input.horizontalAlignment = .stretch
        let roles = self.document.project.roles
        let role = ComboBox(); role.header = "Pour"; role.minWidth = 0; role.horizontalAlignment = .stretch
        role.items.append("Tous les rôles")
        for item in roles { role.items.append(item.name) }
        role.selectedIndex = Int32(roles.firstIndex(where: { $0.id == search.roleID }).map { $0 + 1 } ?? 0)
        let exactCase = CheckBox(); exactCase.content = "Respecter la casse"; exactCase.isChecked = search.caseSensitive
        let wholeWord = CheckBox(); wholeWord.content = "Mot entier"; wholeWord.isChecked = search.wholeWord
        let message = label("", size: 12, color: ink(dark ? 0xB8B8B8 : 0x606060))
        message.textWrapping = .wrap; message.minHeight = 18
        let options = stack([label("Options", size: 12, color: ink(dark ? 0xB8B8B8 : 0x606060)), exactCase, wholeWord], spacing: 0)
        options.margin = Thickness(left: 0, top: 4, right: 0, bottom: 0)
        let content = stack([input, role, options, message], spacing: 16)
        content.width = 360
        func remember() {
            self.search.text = input.text
            let index = Int(role.selectedIndex) - 1
            self.search.roleID = roles.indices.contains(index) ? roles[index].id : nil
            self.search.caseSensitive = exactCase.isChecked ?? false
            self.search.wholeWord = wholeWord.isChecked ?? false
        }
        content.loaded.addHandler { [weak self] _, _ in
            self?.activeDialog?.isPrimaryButtonEnabled = !input.text.isEmpty
            _ = try? input.focus(.programmatic)
            try? input.selectAll()
        }
        role.selectionChanged.addHandler { _, _ in message.text = "" }
        for option in [exactCase, wholeWord] {
            option.checked.addHandler { _, _ in message.text = "" }
            option.unchecked.addHandler { _, _ in message.text = "" }
        }
        input.textChanged.addHandler { [weak self] _, _ in
            message.text = ""
            self?.activeDialog?.isPrimaryButtonEnabled = !input.text.isEmpty
        }
        _ = await dialog("Rechercher", content: content, primary: "Suivant", close: "Annuler", validatePrimary: {
            remember()
            message.text = self.selectNextSearchResult() ? "" : "Aucune phrase trouvée."
            return false // Keep the search open for subsequent matches.
        }, contentWidth: 360, defaultButton: .primary)
        remember()
    }

    func selectNextSearchResult() -> Bool {
        guard !search.text.isEmpty else { return false }
        media.stop()
        self.document.finishEditing()
        guard let cue = search.next(in: self.document.project.cues, after: self.document.frame,
                                    selection: self.document.selection) else { return false }
        self.document.selection = cue.id; self.document.signSelection = nil; self.document.track = cue.track
        seek(cue.start); refreshScript(); updateTextEditor()
        try? scriptRows[cue.id]?.border.startBringIntoView()
        return true
    }

    func findNext() {
        if search.text.isEmpty { Task { await find() }; return }
        if !selectNextSearchResult() { Task { await showError("Aucune phrase trouvée.") } }
    }
}
