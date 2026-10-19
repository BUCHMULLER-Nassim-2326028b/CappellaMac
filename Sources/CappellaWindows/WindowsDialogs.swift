import Foundation
import CappellaCore
import UWP
import WinUI
import WindowsFoundation

extension WindowsEditor {
    func form(_ title: String, fields: [(String, TextBox)]) async -> Bool {
        let panel = StackPanel(); panel.spacing = 10
        for (name, field) in fields { panel.children.append(label(name)); panel.children.append(field) }
        let scroll = ScrollViewer(); scroll.content = panel; scroll.maxHeight = 480; scroll.minWidth = 430
        return await dialog(title, content: scroll, primary: "OK", close: "Annuler") == .primary
    }
    func chooseMedia(audio: Bool) async {
        guard let url = await pickFile(audio ? [".wav", ".aiff", ".aif", ".mp3", ".m4a", ".flac", ".mp4"] : [".mp4", ".mov", ".mkv", ".avi", ".wmv"]) else { return }
        perform {
            try self.document.commit { if audio { $0.audioPath = url.path } else { $0.videoPath = url.path } }
            try media.open(videoPath: self.document.project.videoPath, audioPath: self.document.project.audioPath)
            media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
        }
        refresh()
    }
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
    func newPhrase(edit: Bool = true, kind: String = "in_open", text: String = "") async {
        media.stop()
        guard let role = await chooseRole() else { return }
        perform {
            try self.document.createPhrase(role: role, text: text, edit: edit)
            try self.document.mutateCue { cue in var signs = cue.anchors; signs[0].kind = kind; cue.signs = signs }
        }
        updateTextEditor(focus: edit)
    }
    func toggleEditing() async {
        media.stop()
        if self.document.editing { self.document.finishEditing(); refresh(); return }
        if let cue = self.document.project.cues.last(where: { $0.track == self.document.track && $0.start <= self.document.frame && $0.end >= self.document.frame }) {
            self.document.beginEditing(cue, at: self.document.frame); updateTextEditor(focus: true)
        } else { await newPhrase() }
    }
    func roles() async {
        var roles = self.document.project.roles
        let list = ListView(); list.width = 190; list.height = 320
        let name = textField(), description = textField(), color = textField()
        description.acceptsReturn = true; description.height = 80
        let portrait = Image(); portrait.width = 128; portrait.height = 128; portrait.stretch = .uniform
        let formError = label(""); formError.textWrapping = .wrap
        var selected = 0, loading = false
        func flush() {
            guard !loading, roles.indices.contains(selected) else { return }
            roles[selected].name = name.text; roles[selected].descriptionText = description.text
            roles[selected].hexColor = color.text
        }
        func load() {
            loading = true; defer { loading = false }
            guard roles.indices.contains(selected) else { return }
            name.text = roles[selected].name; description.text = roles[selected].descriptionText ?? ""
            color.text = roles[selected].hexColor ?? "#000000"; portrait.source = nil
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
        let fields = stack([portrait, label("Nom"), name, label("Couleur (#RRGGBB)"), color, label("Description"), description, imageButton, formError])
        fields.width = 270
        let panel = row([stack([list, row([add, remove])]), fields], spacing: 16)
        if await dialog("Rôles", content: panel, primary: "OK", close: "Annuler") == .primary {
            flush(); perform { try self.document.commit { $0.roles = roles } }
        }
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
    func properties() async {
        let title = textField(self.document.project.title), author = textField(self.document.project.author)
        let video = textField(self.document.project.videoPath ?? ""), sound = textField(self.document.project.audioPath ?? "")
        let stamp = textField(Timecode.format(self.document.project.mediaStartFrame, fps: fps))
        let summary = textField(self.document.project.metadata?["summary"] ?? "")
        summary.acceptsReturn = true; summary.height = 90
        guard await form("Propriétés — Fichiers et programme", fields: [("Image", video), ("Son", sound), ("Titre", title), ("Auteur", author), ("Timestamp de l'image", stamp), ("Description", summary)]) else { return }
        do {
            guard let origin = Timecode.parse(stamp.text, fps: fps) else { throw ProjectError.invalid("Timecode invalide.") }
            try self.document.commit { project in
                let delta = origin - project.mediaStartFrame
                if delta != 0 { try project.shift(by: delta, includingMediaOrigin: true) }
                project.title = title.text; project.author = author.text; project.videoPath = video.text.isEmpty ? nil : video.text
                project.audioPath = sound.text.isEmpty ? nil : sound.text
                if project.metadata == nil { project.metadata = [:] }; project.metadata?["summary"] = summary.text
            }
            try media.open(videoPath: self.document.project.videoPath, audioPath: self.document.project.audioPath)
            refresh()
        } catch { await showError(error.localizedDescription) }
    }
    func preferences() async {
        var draft = self.document.preferences
        let theme = ComboBox(); theme.items.append("Clair"); theme.items.append("Sombre"); theme.selectedIndex = dark ? 1 : 0
        let automatic = CheckBox(); automatic.content = "Activer la sauvegarde automatique"; automatic.isChecked = draft.automaticSave
        let interval = textField(String(draft.saveInterval))
        let prefix = CheckBox(); prefix.content = "Préfixer les copies par « Copie de »"; prefix.isChecked = draft.prefixCopies
        let closeReactions = CheckBox(); closeReactions.content = "Fermer automatiquement les réacs"; closeReactions.isChecked = draft.closeReactions
        let font = textField(fontFamily), size = textField(String(Int(draft.fontSize)))
        let speed = textField(String(Int(draft.pixelsPerSecond))), height = textField(String(Int(draft.bandHeight)))
        let panel = stack([label("Général", size: 17), label("Apparence"), theme, prefix, label("Sauvegarde automatique", size: 17), automatic, label("Intervalle (minutes)"), interval, label("Bande rythmo", size: 17), closeReactions, label("Police"), font, label("Taille"), size, label("Échelle horizontale (pixels par seconde)"), speed, label("Hauteur"), height])
        let scroll = ScrollViewer(); scroll.content = panel; scroll.height = 450; scroll.width = 450
        if await dialog("Préférences", content: scroll, primary: "OK", close: "Annuler") == .primary {
            draft.appearance = theme.selectedIndex == 1 ? "dark" : "light"
            draft.automaticSave = automatic.isChecked ?? false; draft.prefixCopies = prefix.isChecked ?? true
            draft.closeReactions = closeReactions.isChecked ?? false
            draft.saveInterval = min(120, max(1, Int(interval.text) ?? 5))
            draft.fontName = font.text; draft.fontSize = min(42, max(16, Double(size.text) ?? 28))
            draft.pixelsPerSecond = min(800, max(15, Double(speed.text) ?? 320)); draft.bandHeight = min(260, max(120, Double(height.text) ?? 146))
            draft.save(); self.document.preferences = draft; refresh()
        }
    }
    func goTimecode() async {
        let input = textField(Timecode.format(self.document.frame, fps: fps))
        if await form("Aller au timecode", fields: [("HH:MM:SS:II", input)]) {
            guard let frame = Timecode.parse(input.text, fps: fps) else { await showError("Timecode invalide."); return }
            media.stop(); seek(frame)
        }
    }
    func shift() async {
        let input = textField("0")
        if await form("Décaler la rythmo", fields: [("Décalage en images (+ ou −)", input)]), let delta = Int(input.text) {
            perform { try self.document.commit { try $0.shift(by: delta) } }
        }
    }
    func find() async {
        let input = textField()
        guard await form("Rechercher", fields: [("Texte", input)]), !input.text.isEmpty else { return }
        let matches = self.document.project.cues.sorted { $0.start < $1.start }.filter { $0.text.localizedCaseInsensitiveContains(input.text) }
        if let cue = matches.first(where: { $0.start > self.document.frame }) ?? matches.first {
            self.document.selection = cue.id; self.document.track = cue.track; media.stop(); seek(cue.start); refreshScript()
        } else { await showError("Texte introuvable.") }
    }
    func markPosition() {
        perform { try self.document.commit { let count = $0.positions?.count ?? 0; if $0.positions == nil { $0.positions = [] }; $0.positions?.append(Marker(frame: self.document.frame, label: "Position \(count + 1)")) } }
    }
    func copyPhrase(cut: Bool = false) {
        guard let cue = self.document.selectedCue, let data = try? JSONEncoder().encode(cue) else { return }
        serializedClipboard = data
        let package = DataPackage(); try? package.setText(cue.text)
        try? package.setData("org.cappella.phrase", data.base64EncodedString())
        try? Clipboard.setContent(package)
        if cut { perform { try self.document.deletePhrase() } }
    }
    func pastePhrase() async {
        do {
            guard let clipboard = try Clipboard.getContent(), try clipboard.contains("org.cappella.phrase"),
                  let value = try await clipboard.getDataAsync("org.cappella.phrase").get() as? String,
                  let data = Data(base64Encoded: value), var cue = try? JSONDecoder().decode(Cue.self, from: data) else { return }
            let delta = self.document.frame - cue.start
            cue.id = UUID(); cue.sourceIndex = nil; cue.track = self.document.track
            var signs = cue.anchors
            cue.start += delta; cue.end += delta
            for index in signs.indices { signs[index].id = UUID(); signs[index].sourceIndex = nil; signs[index].frame += delta }
            cue.signs = signs
            guard !self.document.project.cues.contains(where: { $0.track == cue.track && $0.start < cue.end && $0.end > cue.start }) else { throw ProjectError.invalid("Une phrase occupe déjà la destination.") }
            if !self.document.project.roles.contains(where: { $0.id == cue.roleID }) { cue.roleID = await chooseRole() }
            try self.document.commit { $0.cues.append(cue) }; self.document.selection = cue.id; refresh()
        } catch { await showError(error.localizedDescription) }
    }
    func exportText(crossTable: Bool) async {
        do {
            let picker = FileSavePicker(); try attachPicker(picker)
            picker.suggestedFileName = self.document.project.title
            picker.fileTypeChoices.insert(crossTable ? "Croisillé CSV" : "Script texte", [crossTable ? ".csv" : ".txt"].toVector())
            guard let file = try await picker.pickSaveFileAsync().get() else { return }
            let text = crossTable ? self.document.project.crossTableCSV() : self.document.project.scriptText()
            try text.write(to: URL(fileURLWithPath: file.path), atomically: true, encoding: .utf8)
        } catch { await showError(error.localizedDescription) }
    }
    func showProjection() {
        if let projection { try? projection.activate(); return }
        let projection = Window(); projection.title = "Cappella — Écran de contrôle"
        let video = MediaPlayerElement(); video.areTransportControlsEnabled = false
        try? video.setMediaPlayer(media.video); projection.content = video
        projection.closed.addHandler { [weak self] _, _ in self?.projection = nil; self?.projectionVideo = nil }
        self.projection = projection; projectionVideo = video; try? projection.activate()
    }
    func about() async {
        let logo = Image(); logo.width = 220; logo.height = 165; logo.stretch = .uniform
        let path = resources.appendingPathComponent(dark ? "CappellaLogo_dark.png" : "CappellaLogo.png")
        if FileManager.default.fileExists(atPath: path.path) { logo.source = BitmapImage(Uri(path.absoluteString)) }
        _ = await dialog("À propos de Cappella", content: stack([logo, label("Cappella", size: 26), label("Version Windows — Swift / WinRT"), label("nvssgoat")]), primary: "OK")
    }
}
