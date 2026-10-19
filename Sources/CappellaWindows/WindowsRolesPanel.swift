import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func chooseRole() async -> UUID? {
        let list = ListView(); list.height = 250; list.width = 240
        for role in self.document.project.roles { list.items.append(role.name) }
        list.selectedIndex = Int32(self.document.project.roles.firstIndex { $0.id == self.document.selectedCue?.roleID } ?? 0)
        let portrait = Image(); portrait.width = 128; portrait.height = 128; portrait.stretch = .uniform
        func updatePortrait() {
            let index = Int(list.selectedIndex)
            portrait.source = nil
            guard self.document.project.roles.indices.contains(index), let bytes = self.document.project.roles[index].imageData else { return }
            Task { @MainActor in await self.setImage(portrait, data: bytes) }
        }
        list.selectionChanged.addHandler { _, _ in updatePortrait() }; updatePortrait()
        let name = textField(placeholder: "Nom du nouveau rôle")
        let panel = stack([row([list, portrait], spacing: 18), label("Ou créer un rôle :"), name])
        guard await dialog("Rôles", content: panel, primary: "OK", close: "Annuler") == .primary else { return nil }
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
        let list = ListView(); list.width = 190; list.height = 320
        let name = textField(), description = textField(), color = textField()
        let gender = ComboBox()
        for title in ["Neutre", "Masculin", "Féminin"] { gender.items.append(title) }
        description.acceptsReturn = true; description.height = 80
        let portrait = Image(); portrait.width = 128; portrait.height = 128; portrait.stretch = .uniform
        let formError = label(""); formError.textWrapping = .wrap
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
        let fields = stack([portrait, label("Nom"), name, label("Couleur (#RRGGBB)"), color, label("Genre"), gender, label("Description"), description, imageButton, formError])
        fields.width = 270
        let panel = row([stack([list, row([add, remove])]), fields], spacing: 16)
        _ = await dialog("Rôles", content: panel, primary: "OK", close: "Annuler", validatePrimary: {
            flush()
            do { try self.document.commit { $0.roles = roles }; return true }
            catch { formError.text = error.localizedDescription; return false }
        })
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
