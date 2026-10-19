import Foundation
import CappellaCore
import UWP
import WinUI
import WindowsFoundation

extension WindowsEditor {
    func dialog(_ title: String, content: UIElement, primary: String = "OK", secondary: String = "", close: String = "", validatePrimary: (() -> Bool)? = nil, secondaryAction: (() -> Void)? = nil, contentWidth: Double? = nil) async -> ContentDialogResult {
        guard !dialogShowing, !isClosed else { return .none }
        dialogShowing = true; defer { dialogShowing = false }
        let dialog = ContentDialog(); dialog.title = title; dialog.content = content
        activeDialog = dialog
        defer { if activeDialog === dialog { activeDialog = nil } }
        dialog.requestedTheme = dark ? .dark : .light
        if let contentWidth {
            let width = contentWidth + 48
            _ = dialog.resources.insert("ContentDialogMaxWidth", width)
            // ContentDialog itself spans the XamlRoot for popup layout. Limit
            // only its inner surface through the native theme resource.
        }
        dialog.xamlRoot = root.xamlRoot; dialog.primaryButtonText = primary
        dialog.secondaryButtonText = secondary; dialog.closeButtonText = close
        if let validatePrimary {
            dialog.primaryButtonClick.addHandler { _, args in args?.cancel = !validatePrimary() }
        }
        if let secondaryAction {
            dialog.secondaryButtonClick.addHandler { _, args in args?.cancel = true; secondaryAction() }
        }
        do { return try await dialog.showAsync().get() } catch { status.text = error.localizedDescription; return .none }
    }

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
        // Keep the actual Swift projections alive in the handler. Reading their
        // native selection state avoids casting boxed IInspectable content or
        // comparing freshly projected event objects with the original wrappers.
        let content = Grid()
        for (index, page) in pages.enumerated() {
            page.visibility = index == 0 ? .visible : .collapsed
            content.children.append(page)
        }
        navigation.content = content
        navigation.selectionChanged.addHandler { _, _ in
            guard let selected = items.firstIndex(where: { $0.isSelected }) else { return }
            for (index, page) in pages.enumerated() {
                page.visibility = index == selected ? .visible : .collapsed
            }
        }
        if let first = items.first { navigation.selectedItem = first }
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
