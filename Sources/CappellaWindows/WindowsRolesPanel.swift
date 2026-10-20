import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func chooseRole(preferred: UUID? = nil) async -> UUID? {
        let list = ListView(); list.height = 280; list.minWidth = 0
        for role in self.document.project.roles { list.items.append(role.name) }
        list.selectedIndex = self.document.project.roles.isEmpty ? -1 : Int32(self.document.project.roles.firstIndex { $0.id == (preferred ?? self.document.selectedCue?.roleID) } ?? 0)
        let portrait = Image(); portrait.width = 128; portrait.height = 128; portrait.stretch = .uniform
        func updatePortrait() {
            let index = Int(list.selectedIndex)
            portrait.source = nil
            guard self.document.project.roles.indices.contains(index), let bytes = self.document.project.roles[index].imageData else { return }
            Task { @MainActor in await self.setImage(portrait, data: bytes) }
        }
        list.selectionChanged.addHandler { _, _ in updatePortrait() }; updatePortrait()
        let name = textField(placeholder: "Nom du nouveau rôle")
        name.header = "Créer un rôle"
        let choice = Grid(); choice.columnSpacing = 20
        let listColumn = ColumnDefinition(); listColumn.width = GridLength(value: 1, gridUnitType: .star)
        let portraitColumn = ColumnDefinition(); portraitColumn.width = GridLength(value: 128, gridUnitType: .pixel)
        choice.columnDefinitions.append(listColumn); choice.columnDefinitions.append(portraitColumn)
        choice.children.append(dialogField("Rôles du projet", list))
        let preview = dialogField("Portrait", portrait); preview.verticalAlignment = .top
        try? Grid.setColumn(preview, 1); choice.children.append(preview)
        let panel = stack([choice, name, dialogHint("Choisissez un rôle dans la liste, ou saisissez le nom d'un nouveau rôle.")], spacing: 16)
        panel.width = 520
        guard await dialog("Choisir un rôle", content: panel, primary: "OK", close: "Annuler",
                           contentWidth: 520, defaultButton: .primary) == .primary else { return nil }
        let newName = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            if let existing = self.document.project.roles.first(where: { $0.name.localizedCaseInsensitiveCompare(newName) == .orderedSame }) { return existing.id }
            let role = Role(name: newName, color: self.document.project.roles.count % 6)
            do { try self.document.commit { $0.roles.append(role) }; return role.id }
            catch { await showError(error.localizedDescription); return nil }
        }
        let index = Int(list.selectedIndex)
        return self.document.project.roles.indices.contains(index) ? self.document.project.roles[index].id : nil
    }
    func roles() async {
        var roles = self.document.project.roles
        let list = ListView(); list.width = 200; list.height = 390
        let name = textField(), description = textField(), color = textField()
        let gender = ComboBox()
        for title in ["Neutre", "Masculin", "Féminin"] { gender.items.append(title) }
        description.acceptsReturn = true; description.textWrapping = .wrap; description.height = 110
        let portrait = Image(); portrait.width = 128; portrait.height = 128; portrait.stretch = .uniform
        let formError = dialogError()
        var selected = 0, loading = false
        func flush() {
            guard !loading, roles.indices.contains(selected) else { return }
            roles[selected].name = name.text; roles[selected].descriptionText = description.text
            roles[selected].hexColor = color.text
            let genders = ["neutral", "male", "female"], index = Int(gender.selectedIndex)
            roles[selected].gender = genders.indices.contains(index) ? genders[index] : "neutral"
        }
        func load() {
            loading = true; defer { loading = false }
            guard roles.indices.contains(selected) else { return }
            name.text = roles[selected].name; description.text = roles[selected].descriptionText ?? ""
            color.text = roles[selected].hexColor ?? "#000000"; portrait.source = nil
            gender.selectedIndex = Int32(["neutral", "male", "female"].firstIndex(of: roles[selected].gender ?? "neutral") ?? 0)
            if let data = roles[selected].imageData { Task { @MainActor in await self.setImage(portrait, data: data) } }
        }
        func reload() {
            loading = true
            list.items.clear(); for role in roles { list.items.append(role.name) }
            list.selectedIndex = roles.isEmpty ? -1 : Int32(min(selected, roles.count - 1))
            loading = false; load()
        }
        list.selectionChanged.addHandler { _, _ in
            guard !loading else { return }
            flush(); let next = Int(list.selectedIndex); if roles.indices.contains(next) { selected = next; load() }
        }
        let add = button("Nouveau…") {
            flush(); var number = roles.count + 1
            while roles.contains(where: { $0.name == "Rôle \(number)" }) { number += 1 }
            roles.append(Role(name: "Rôle \(number)", color: roles.count % 6)); selected = roles.count - 1; reload()
        }
        let remove = button("Supprimer") {
            guard roles.indices.contains(selected) else { return }
            if self.document.project.cues.contains(where: { $0.roleID == roles[selected].id }) { formError.text = "Ce rôle est attribué à une phrase."; return }
            roles.remove(at: selected); selected = max(0, selected - 1); reload()
        }
        let imageButton = button("Choisir un portrait…") { [unowned self] in
            Task { @MainActor in
                guard let url = await pickFile([".png", ".jpg", ".jpeg", ".bmp"]), roles.indices.contains(selected) else { return }
                do {
                    let data = try Data(contentsOf: url)
                    guard data.count < 5_000_000 else { throw ProjectError.invalid("Choisir un portrait de moins de 5 Mo.") }
                    roles[selected].imageData = data; await setImage(portrait, data: data)
                } catch { formError.text = error.localizedDescription }
            }
        }
        reload()
        portrait.width = 96; portrait.height = 96; portrait.verticalAlignment = .top
        imageButton.horizontalAlignment = .left
        let portraitHint = dialogHint("PNG, JPEG ou BMP · 5 Mo maximum"); portraitHint.maxWidth = 200
        let imageActions = stack([imageButton, portraitHint], spacing: 8)
        let fields = stack([
            dialogSection("Portrait", [row([portrait, imageActions], spacing: 16)]),
            dialogField("Nom", name),
            dialogColumns([dialogField("Couleur (#RRGGBB)", color), dialogField("Genre", gender)]),
            dialogField("Description", description)
        ], spacing: 16)
        let details = ScrollViewer(); details.content = fields; details.maxHeight = 450
        details.horizontalScrollBarVisibility = .disabled; details.verticalScrollBarVisibility = .auto
        add.minWidth = 0; remove.minWidth = 0
        let sidebar = stack([label("Rôles du projet"), list, row([add, remove], spacing: 8)], spacing: 12)
        let layout = Grid(); layout.columnSpacing = 24
        let sidebarColumn = ColumnDefinition(); sidebarColumn.width = GridLength(value: 200, gridUnitType: .pixel)
        let detailsColumn = ColumnDefinition(); detailsColumn.width = GridLength(value: 1, gridUnitType: .star)
        layout.columnDefinitions.append(sidebarColumn); layout.columnDefinitions.append(detailsColumn)
        layout.children.append(sidebar); try? Grid.setColumn(details, 1); layout.children.append(details)
        let panel = stack([layout, formError], spacing: 16); panel.width = 580
        _ = await dialog("Rôles", content: panel, primary: "OK", close: "Annuler", validatePrimary: {
            flush()
            do { try self.document.commit { $0.roles = roles }; return true }
            catch { formError.text = error.localizedDescription; return false }
        }, contentWidth: 580)
    }
    func setImage(_ view: Image, data: Data) async {
        do {
            let stream = InMemoryRandomAccessStream()
            let writer = DataWriter(try stream.getOutputStreamAt(0))
            try writer.writeBytes(Array(data)); _ = try await writer.storeAsync().get()
            try stream.seek(0)
            let bitmap = BitmapImage(); try await bitmap.setSourceAsync(stream).get(); view.source = bitmap
        } catch { view.source = nil }
    }
}
