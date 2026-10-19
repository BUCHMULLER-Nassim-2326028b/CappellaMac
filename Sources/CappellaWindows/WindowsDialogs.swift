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
            try loadProjectMedia()
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
    // Fixed left-hand categories with native selection and retained draft pages.
    func dialogCategories(_ sections: [(String, UIElement)]) -> NavigationView {
        let navigation = NavigationView()
        navigation.paneDisplayMode = .left
        navigation.isPaneOpen = true; navigation.openPaneLength = 170
        navigation.isPaneToggleButtonVisible = false
        navigation.isBackButtonVisible = .collapsed
        navigation.isSettingsVisible = false; navigation.alwaysShowHeader = false
        navigation.width = 660; navigation.height = 410
        var items: [NavigationViewItem] = []
        var pages: [ScrollViewer] = []
        for section in sections {
            let item = NavigationViewItem(); item.content = section.0
            navigation.menuItems.append(item); items.append(item)
            let page = ScrollViewer(); page.content = section.1
            page.padding = Thickness(left: 16, top: 8, right: 8, bottom: 8)
            pages.append(page)
        }
        let names = sections.map { $0.0 }
        navigation.selectionChanged.addHandler { sender, args in
            guard let sender else { return }
            let selected = args?.selectedItem as? NavigationViewItem
            let title = (selected?.content as? String) ?? (args?.selectedItemContainer?.content as? String)
            guard let title, let index = names.firstIndex(of: title) else { return }
            sender.content = pages[index]
        }
        if let first = items.first {
            navigation.content = pages.first
            navigation.selectedItem = first
        }
        return navigation
    }
    func dialogField(_ title: String, _ control: FrameworkElement) -> Grid {
        let grid = Grid()
        let caption = ColumnDefinition(); caption.width = GridLength(value: 155, gridUnitType: .pixel)
        let value = ColumnDefinition(); value.width = GridLength(value: 1, gridUnitType: .star)
        grid.columnDefinitions.append(caption); grid.columnDefinitions.append(value)
        let text = label(title); text.verticalAlignment = .center; text.textWrapping = .wrap
        grid.children.append(text); try? Grid.setColumn(control, 1); grid.children.append(control)
        return grid
    }
    func properties() async {
        media.stop()
        var draft = self.document.project
        let title = textField(draft.title), author = textField(draft.author)
        let video = textField(draft.videoPath ?? ""), sound = textField(draft.audioPath ?? "")
        let rolesFile = textField(draft.metadata?["roles-file"] ?? ""); rolesFile.isReadOnly = true
        let stamp = textField(Timecode.format(draft.mediaStartFrame, fps: fps))
        let errorText = label(""); errorText.textWrapping = .wrap
        var metadataFields: [(String, TextBox)] = []
        func metadataField(_ name: String, _ key: String) -> Grid {
            let field = textField(draft.metadata?[key] ?? "")
            metadataFields.append((key, field))
            return dialogField(name, field)
        }
        func browseRow(_ name: String, _ field: TextBox, kind: Int) -> Grid {
            let browse = button("Parcourir…") { [unowned self] in
                Task { @MainActor in
                    let extensions = kind == 0 ? [".mp4", ".mov", ".mkv", ".avi", ".wmv"] :
                        kind == 1 ? [".wav", ".aiff", ".aif", ".mp3", ".m4a", ".flac", ".mp4"] : [".detx", ".xml"]
                    guard let url = await self.pickFile(extensions, onError: { errorText.text = $0 }) else { return }
                    do {
                        if kind == 2 {
                            let imported = try DetX.read(Data(contentsOf: url), fps: draft.framesPerSecond)
                            for candidate in imported.roles where !draft.roles.contains(where: {
                                $0.name.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame
                            }) {
                                var role = candidate; role.id = UUID(); role.sourceID = nil
                                draft.roles.append(role)
                            }
                        }
                        field.text = url.path; errorText.text = ""
                    } catch { errorText.text = error.localizedDescription }
                }
            }
            let grid = Grid()
            let pathColumn = ColumnDefinition(); pathColumn.width = GridLength(value: 1, gridUnitType: .star)
            let browseColumn = ColumnDefinition(); browseColumn.width = GridLength(value: 110, gridUnitType: .pixel)
            grid.columnDefinitions.append(pathColumn); grid.columnDefinitions.append(browseColumn)
            grid.children.append(field); try? Grid.setColumn(browse, 1); grid.children.append(browse)
            return dialogField(name, grid)
        }
        let files = stack([browseRow("Image", video, kind: 0), browseRow("Son", sound, kind: 1),
                           browseRow("Liste des rôles", rolesFile, kind: 2)], spacing: 18)
        let cadence = ComboBox()
        for rate in [24, 25, 30] { cadence.items.append("\(rate) i/s") }
        cadence.selectedIndex = Int32([24, 25, 30].firstIndex(of: fps) ?? 1)
        cadence.isEnabled = draft.cues.isEmpty && draft.originalDetX == nil
        let programme = stack([
            dialogField("Titre original", title), metadataField("Titre français", "title2"),
            metadataField("Épisode", "episode.number"), metadataField("Saison", "episode.season"),
            metadataField("Titre de l'épisode", "episode.title"),
            metadataField("Titre français de l'épisode", "episode.title2"),
            dialogField("Auteur", author),
            metadataField("Second auteur — prénom", "second-author.firstname"),
            metadataField("Second auteur — nom", "second-author.name"),
            metadataField("Détecteur — prénom", "detector.firstname"),
            metadataField("Détecteur — nom", "detector.name"),
            dialogField("Cadence", cadence), dialogField("Timestamp de l'image", stamp)
        ])
        let production = stack([
            metadataField("Année", "production.year"), metadataField("Pays", "production.country"),
            metadataField("Réalisateur", "production.director"), metadataField("Producteur", "production.producer"),
            metadataField("Distributeur", "production.distributor"), metadataField("Diffuseur", "production.diffuser"),
            metadataField("Acteurs principaux", "production.actors")
        ])
        let summary = textField(draft.metadata?["summary"] ?? "")
        let notes = textField(draft.metadata?["notes"] ?? "")
        for field in [summary, notes] { field.acceptsReturn = true; field.textWrapping = .wrap; field.height = 140 }
        metadataFields.append(("summary", summary)); metadataFields.append(("notes", notes))
        let description = stack([label("Résumé"), summary, label("Notes"), notes])
        var markerFields: [(UUID, TextBox, TextBox)] = []
        var removedMarkers = Set<UUID>()
        func markers(_ name: String, _ markers: [Marker]) -> StackPanel {
            let panel = stack([label(name, size: 17)])
            if markers.isEmpty { panel.children.append(label("Aucun repère.")) }
            for marker in markers {
                let number = textField(marker.label); number.width = 70
                let time = textField(Timecode.format(marker.frame, fps: fps)); time.width = 145
                let line = row([number, time])
                line.children.append(button("Supprimer") { [weak line] in
                    removedMarkers.insert(marker.id); line?.visibility = .collapsed
                })
                markerFields.append((marker.id, number, time)); panel.children.append(line)
            }
            return panel
        }
        let references = stack([markers("Boucles", draft.loops), markers("Changements de plan", draft.shots)], spacing: 20)
        let categories = dialogCategories([("Fichier", files), ("Programme", programme), ("Production", production),
                               ("Description", description), ("Repères", references)])
        func apply() -> Bool {
            do {
                var next = draft
                let rates = [24, 25, 30], rateIndex = Int(cadence.selectedIndex)
                guard rates.indices.contains(rateIndex) else { throw ProjectError.invalid("Cadence invalide.") }
                next.framesPerSecond = rates[rateIndex]
                guard let origin = Timecode.parse(stamp.text, fps: next.framesPerSecond) else {
                    throw ProjectError.invalid("Timestamp de l'image invalide.")
                }
                next.title = title.text; next.author = author.text
                next.videoPath = video.text.isEmpty ? nil : video.text
                next.audioPath = sound.text.isEmpty ? nil : sound.text
                if next.metadata == nil { next.metadata = [:] }
                next.metadata?["roles-file"] = rolesFile.text
                for (key, field) in metadataFields { next.metadata?[key] = field.text }
                next.loops.removeAll { removedMarkers.contains($0.id) }
                next.shots.removeAll { removedMarkers.contains($0.id) }
                for (id, number, time) in markerFields where !removedMarkers.contains(id) {
                    guard let frame = Timecode.parse(time.text, fps: next.framesPerSecond) else {
                        throw ProjectError.invalid("Timecode invalide pour le repère « \(number.text) ».")
                    }
                    if let index = next.loops.firstIndex(where: { $0.id == id }) {
                        next.loops[index].label = number.text; next.loops[index].frame = frame
                    } else if let index = next.shots.firstIndex(where: { $0.id == id }) {
                        next.shots[index].label = number.text; next.shots[index].frame = frame
                    }
                }
                let delta = origin - next.mediaStartFrame
                if delta != 0 { try next.shift(by: delta, includingMediaOrigin: true) }
                let previous = self.document.project
                try self.document.commit { $0 = next }
                draft = next; errorText.text = ""
                for (id, _, time) in markerFields {
                    if let marker = (next.loops + next.shots).first(where: { $0.id == id }) {
                        time.text = Timecode.format(marker.frame, fps: next.framesPerSecond)
                    }
                }
                // Apply can be clicked repeatedly. Only rebuild the media graph
                // when its paths changed; metadata edits keep the loaded media.
                if previous.videoPath != next.videoPath || previous.audioPath != next.audioPath {
                    try loadProjectMedia()
                }
                refresh(); return true
            } catch { errorText.text = error.localizedDescription; return false }
        }
        _ = await dialog("Propriétés", content: stack([categories, errorText]), primary: "OK",
                         secondary: "Appliquer", close: "Annuler",
                         validatePrimary: apply, secondaryAction: { _ = apply() }, contentWidth: 660)
    }
    func preferences() async {
        var draft = self.document.preferences
        func check(_ title: String, _ value: Bool) -> CheckBox {
            let view = CheckBox(); view.content = title; view.isChecked = value; return view
        }
        let theme = ComboBox(); theme.items.append("Clair"); theme.items.append("Sombre"); theme.selectedIndex = dark ? 1 : 0
        let updates = check("Vérifier les mises à jour au lancement", draft.checkUpdates)
        let prefix = check("Préfixer les copies enregistrées par « Copie de »", draft.prefixCopies)
        let automatic = check("Activer la sauvegarde automatique", draft.automaticSave)
        let interval = textField(String(draft.saveInterval)); interval.isEnabled = draft.automaticSave
        automatic.checked.addHandler { _, _ in interval.isEnabled = true }
        automatic.unchecked.addHandler { _, _ in interval.isEnabled = false }
        let general = stack([label("Général", size: 17), updates, prefix, dialogField("Apparence", theme),
                             label("Sauvegarde automatique", size: 17), automatic, dialogField("Intervalle (minutes)", interval)])
        let closeReactions = check("Fermer automatiquement les réacs", draft.closeReactions)
        let font = textField(fontFamily), size = textField(String(Int(draft.fontSize)))
        let speed = textField(String(Int(draft.pixelsPerSecond))), height = textField(String(Int(draft.bandHeight)))
        let grid = check("Grille et signes", draft.showGrid), detection = check("Détection", draft.showDetection)
        let band = stack([closeReactions, dialogField("Police", font), dialogField("Taille des répliques", size),
                          dialogField("Pixels par seconde", speed), dialogField("Hauteur de la bande", height), grid, detection])
        let control = check("Afficher l'écran de contrôle au lancement", draft.showControlAtLaunch)
        let offset = textField(String(Int(draft.videoOffsetMilliseconds)))
        let reset = button("Réinitialiser le décalage") { offset.text = "0" }
        let video = stack([control, label("Décalage de l'image par rapport au son"),
                           dialogField("Décalage (ms)", offset), label("Négatif : en retard · Positif : en avance"), reset])
        let categories = dialogCategories([("Général", general), ("Bande rythmo", band), ("Vidéo", video)])
        let errorText = label(""); errorText.textWrapping = .wrap
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
            draft.save(); self.document.preferences = draft
            media.videoOffset = delay / 1000
            media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
            refresh(); return true
        }
        _ = await dialog("Préférences", content: stack([categories, errorText]), primary: "OK", close: "Annuler",
                         validatePrimary: apply, contentWidth: 660)
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
        let projection = Window(); projection.title = "Cappella - Écran de contrôle"
        let video = MediaPlayerElement(); video.areTransportControlsEnabled = false
        try? video.setMediaPlayer(media.video); projection.content = video
        projection.closed.addHandler { [weak self] _, _ in self?.projection = nil; self?.projectionVideo = nil }
        self.projection = projection; projectionVideo = video; try? projection.activate()
    }
    func about() async {
        let logo = Image(); logo.width = 220; logo.height = 165; logo.stretch = .uniform
        let path = resources.appendingPathComponent(dark ? "CappellaLogo_dark.png" : "CappellaLogo.png")
        if FileManager.default.fileExists(atPath: path.path) { logo.source = BitmapImage(Uri(path.absoluteString)) }
        _ = await dialog("À propos de Cappella", content: stack([logo, label("Cappella", size: 26), label("Version 0.9b"), label("nvssgoat")]), primary: "OK")
    }
}
