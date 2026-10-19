import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation
import CWindowsInterop

@MainActor
final class WindowsEditor {
    let window = Window()
    let document = WindowsDocument()
    let media = WindowsMedia()
    let root = Grid()
    let windowChrome = Grid()
    let customTitleBar = Grid()
    let titleText = label("Cappella", size: 12)
    let titleLogo = Image()
    var resizeRegions: [WindowsResizeRegion] = []
    var resizeRegion: WindowsResizeRegion?
    var resizeOrigin = 0.0
    var resizeValue = 0.0
    var resizeDPI = 1.0
    var resizeCoordinate: Double?
    let resizeTimer = DispatcherTimer()
    var handledDesktopKeys = Set<UInt>()
    var isClosed = false
    var onClosed: (() -> Void)?
    var closeApproved = false
    var closePromptActive = false
    let editorAdornments = Canvas()
    let caretTimer = DispatcherTimer()
    var caretVisible = true
    var isResizing = false
    let script = StackPanel()
    var scriptOrder: [UUID] = []
    var scriptRows: [UUID: (border: Border, header: TextBlock, text: TextBlock)] = [:]
    var scriptSelection: UUID?
    var scriptRevision = UInt64.max
    var scriptModels: [UUID: Cue] = [:]
    var scriptRoles: [Role] = []
    var scriptFPS = 0
    var lastWindowTitle: String?
    var appliedDark: Bool?
    var appliedBandHeight = 0.0
    var displayedFrame: Int?
    var displayedFPS = 0
    var displayedLoop: Marker?
    var displayedVI: Bool?
    var renderingSubscription: EventCleanup?
    lazy var bandTextCursor = try? InputSystemCursor.create(.ibeam)
    let band = Canvas()
    let bandBackdrop = Canvas()
    let bandRuler = Canvas()
    let rulerTranslation = CompositeTransform()
    var rulerState: WindowsRulerState?
    let bandOverlay = Canvas()
    let bandTranslation = CompositeTransform()
    let bandMotion = WindowsTimelineMotion()
    let rulerMotion = WindowsTimelineMotion()
    var timelineClock = WindowsTimelineClock()
    var bandCueViews: [UUID: Canvas] = [:]
    var bandMarkerViews: [UUID: Canvas] = [:]
    var lastBandPopulation = -Double.infinity
    var bandOriginFrame = 0
    var bandCacheWidth = 0.0
    var bandCacheHeight = 0.0
    var bandState: WindowsBandState?
    var playbackFrame: Double?
    var lastAutosavePoll = Date.distantPast
    let bandContainer = Grid()
    let editorLayer = Canvas()
    let timecode = label("00:00:00:00", size: 28, color: ink(0xFFFFFF))
    let loopLabel = label("", size: 13, color: ink(0xDDDDDD))
    let videoView = MediaPlayerElement()
    let vo = button("VO", action: {})
    let vi = button("VI", action: {})
    let timer = DispatcherTimer()
    var textEditor: TextBox?
    var textEditorCue: UUID?
    var changingText = false
    var dialogShowing = false
    var activeDialog: ContentDialog?
    var lastTick = Date()
    var lastRenderUptime = ProcessInfo.processInfo.systemUptime
    let editorMeasurement = TextBlock()
    var textSelectionAnchor: (UUID, Int, Double)?
    var dragSign: (UUID, UUID, Int, Double)?
    var dragMoved = false
    var pointerWasLeft = false
    var logicalFrame: Double?
    var undoEditing = false
    var serializedClipboard: Data?
    var projection: Window?
    var projectionVideo: MediaPlayerElement?
    var lastSavedPreference = Date.distantPast
    var previewImage: Image?
    var status = label("")
    var dark: Bool { self.document.preferences.appearance == "dark" }
    var fps: Int { self.document.project.framesPerSecond }
    var scale: Double { self.document.preferences.pixelsPerSecond / Double(max(1, fps)) }
    var resources: URL { URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("Resources") }

    init() {
        window.title = "Cappella"
        try? window.appWindow.resize(SizeInt32(width: 1420, height: 800))
        media.videoOffset = self.document.preferences.videoOffsetMilliseconds / 1000
        buildLayout()
        installWindowChrome()
        root.sizeChanged.addHandler { [weak self] _, _ in self?.fitBandHeight() }
        self.document.changed = { [weak self] in self?.refresh() }
        media.failed = { [weak self] message in Task { @MainActor in await self?.showError(message) } }
        root.previewKeyDown.addHandler { [weak self] _, args in self?.keyDown(args) }
        bandContainer.sizeChanged.addHandler { [weak self] _, _ in self?.renderBand(); self?.updateTextEditor() }
        bandContainer.pointerPressed.addHandler { [weak self] _, args in self?.pointerPressed(args) }
        bandContainer.pointerMoved.addHandler { [weak self] _, args in self?.pointerMoved(args) }
        bandContainer.pointerReleased.addHandler { [weak self] _, args in self?.pointerReleased(args) }
        bandContainer.rightTapped.addHandler { [weak self] _, args in self?.contextMenu(args) }
        vo.click.addHandler { [weak self] _, _ in guard let self else { return }; media.usingVI = false; media.applyAudio(); refreshClock() }
        vi.click.addHandler { [weak self] _, _ in guard let self else { return }; media.usingVI = true; media.applyAudio(); refreshClock() }
        window.appWindow.closing.addHandler { [weak self] _, args in
            guard let self, !closeApproved else { return }
            if self.document.dirty {
                args?.cancel = true
                guard !closePromptActive else { return }
                closePromptActive = true
                Task { @MainActor in
                    defer { self.closePromptActive = false }
                    if await self.mayReplace() { self.closeApproved = true; try? self.window.close() }
                }
            }
        }
        window.activated.addHandler { [weak self] _, args in
            if args?.windowActivationState == .deactivated { self?.endResize() }
        }
        media.playbackChanged = { [weak self] in self?.updatePlaybackRendering() }
        window.closed.addHandler { [weak self] _, _ in self?.shutdown() }
        // Only runs during a divider drag, including when WinUI consumes mouse
        // movement before the desktop pre-translation hook sees it.
        resizeTimer.interval = TimeSpan(duration: 80_000)
        resizeTimer.tick.addHandler { [weak self] _, _ in self?.pollResize() }
        caretTimer.interval = TimeSpan(duration: 5_000_000)
        caretTimer.tick.addHandler { [weak self] _, _ in
            guard let self, self.document.editing else { return }
            caretVisible.toggle(); renderEditorAdornments()
        }
        timer.interval = TimeSpan(duration: 10_000_000)
        timer.tick.addHandler { [weak self] _, _ in self?.pollAutosave() }
        try? timer.start()
        refresh()
    }
    func buildLayout() {
        let menuRow = RowDefinition(); menuRow.height = GridLength(value: 0, gridUnitType: .auto)
        let mainRow = RowDefinition(); mainRow.height = GridLength(value: 1, gridUnitType: .star)
        let bandRow = RowDefinition(); bandRow.height = GridLength(value: max(120, self.document.preferences.bandHeight), gridUnitType: .pixel)
        let dividerRow = RowDefinition(); dividerRow.height = GridLength(value: 6, gridUnitType: .pixel)
        root.rowDefinitions.append(menuRow); root.rowDefinitions.append(mainRow); root.rowDefinitions.append(dividerRow); root.rowDefinitions.append(bandRow)
        let menus = makeMenu(); try? Grid.setRow(menus, 0); root.children.append(menus)
        let main = Grid()
        let storedFraction = UserDefaults.standard.double(forKey: "layout.windows.leftFraction")
        let initialFraction = storedFraction.isFinite && storedFraction > 0 ? min(0.85, max(0.15, storedFraction)) : 0.445
        let leftColumn = ColumnDefinition(); leftColumn.width = GridLength(value: initialFraction, gridUnitType: .star)
        let dividerColumn = ColumnDefinition(); dividerColumn.width = GridLength(value: 6, gridUnitType: .pixel)
        let rightColumn = ColumnDefinition(); rightColumn.width = GridLength(value: 1 - initialFraction, gridUnitType: .star)
        main.columnDefinitions.append(leftColumn); main.columnDefinitions.append(dividerColumn); main.columnDefinitions.append(rightColumn)
        // Retain these Swift projections in the drag callbacks. XAML retaining
        // the native Grid does not retain its original Swift wrapper.
        let verticalDivider = makeResizeHandle(vertical: true, position: { leftColumn.actualWidth }, change: { [main] value in
            let available = max(1, main.actualWidth - 6), minimum = min(240, available * 0.4)
            let fraction = min(available - minimum, max(minimum, value)) / available
            leftColumn.width = GridLength(value: fraction, gridUnitType: .star)
            rightColumn.width = GridLength(value: 1 - fraction, gridUnitType: .star)
        }, finish: { [main] in
            UserDefaults.standard.set(leftColumn.actualWidth / max(1, main.actualWidth - 6), forKey: "layout.windows.leftFraction")
        })
        try? Grid.setColumn(verticalDivider, 1); main.children.append(verticalDivider)
        let left = Grid()
        let scriptRow = RowDefinition(); scriptRow.height = GridLength(value: 1, gridUnitType: .star)
        let savedClockHeight = UserDefaults.standard.double(forKey: "layout.windows.clockHeight")
        let clockRow = RowDefinition(); clockRow.height = GridLength(value: savedClockHeight.isFinite && savedClockHeight >= 76 ? savedClockHeight : 92, gridUnitType: .pixel)
        let clockDividerRow = RowDefinition(); clockDividerRow.height = GridLength(value: 6, gridUnitType: .pixel)
        left.rowDefinitions.append(scriptRow); left.rowDefinitions.append(clockDividerRow); left.rowDefinitions.append(clockRow)
        let clockDivider = makeResizeHandle(vertical: false, position: { -clockRow.actualHeight }, change: { [left] value in
            clockRow.height = GridLength(value: min(max(76, left.actualHeight - 100), max(76, -value)), gridUnitType: .pixel)
        }, finish: { UserDefaults.standard.set(clockRow.actualHeight, forKey: "layout.windows.clockHeight") })
        try? Grid.setRow(clockDivider, 1); left.children.append(clockDivider)
        main.sizeChanged.addHandler { [weak left] _, _ in
            guard let left, left.actualHeight > 0 else { return }
            let maximum = max(76, left.actualHeight - 100)
            if clockRow.actualHeight > maximum { clockRow.height = GridLength(value: maximum, gridUnitType: .pixel) }
        }
        let scroll = ScrollViewer(); scroll.content = script
        script.spacing = 15; script.padding = Thickness(left: 8, top: 16, right: 8, bottom: 16)
        left.children.append(scroll)
        let clock = Border(); clock.background = ink(0x161D23); clock.padding = Thickness(left: 8, top: 4, right: 8, bottom: 4)
        clock.child = stack([row([label("timecode", size: 10, color: ink(0xFFFFFF)), timecode]), loopLabel, row([vo, vi])], spacing: 2)
        try? Grid.setRow(clock, 2); left.children.append(clock)
        main.children.append(left)
        let videoPanel = Grid()
        let mire = Image()
        let path = resources.appendingPathComponent("Mire.jpg")
        if FileManager.default.fileExists(atPath: path.path) { mire.source = BitmapImage(Uri(path.absoluteString)) }
        mire.stretch = .uniformToFill; videoPanel.children.append(mire); previewImage = mire
        videoView.areTransportControlsEnabled = false
        try? videoView.setMediaPlayer(media.video)
        videoPanel.children.append(videoView)
        try? Grid.setColumn(videoPanel, 2); main.children.append(videoPanel)
        try? Grid.setRow(main, 1); root.children.append(main)
        band.renderTransform = bandTranslation
        band.useLayoutRounding = false
        bandRuler.renderTransform = rulerTranslation
        bandRuler.isHitTestVisible = false
        bandContainer.children.append(bandBackdrop)
        bandContainer.children.append(bandRuler)
        bandContainer.children.append(band)
        bandOverlay.isHitTestVisible = false
        bandContainer.children.append(bandOverlay)
        bandContainer.children.append(editorLayer)
        try? Grid.setRow(bandContainer, 3); root.children.append(bandContainer)
        let bandDivider = makeResizeHandle(vertical: false, position: { -bandRow.actualHeight }, change: { [weak self] value in
            guard let self else { return }
            let height = min(max(120, root.actualHeight - 190), max(120, -value))
            self.document.preferences.bandHeight = height; appliedBandHeight = height
            bandRow.height = GridLength(value: height, gridUnitType: .pixel)
        }, finish: { [weak self] in self?.document.preferences.save() })
        try? Grid.setRow(bandDivider, 2); root.children.append(bandDivider)
    }
    func refresh() {
        guard !isClosed else { return }
        let title = self.document.title
        if title != lastWindowTitle { window.title = title; titleText.text = title; lastWindowTitle = title }
        if appliedDark != dark {
            refreshWindowChrome()
            root.requestedTheme = dark ? .dark : .light
            root.background = ink(dark ? 0x202020 : 0xF6F7F8)
            let icon = resources.appendingPathComponent(dark ? "AppIconDark.ico" : "AppIcon.ico").path
            if FileManager.default.fileExists(atPath: icon) { try? window.appWindow.setIcon(icon) }
            appliedDark = dark
        }
        fitBandHeight()

        let visibility: WinUI.Visibility = media.hasVideo ? .visible : .collapsed
        if videoView.visibility != visibility { videoView.visibility = visibility }
        previewImage?.visibility = media.hasVideo ? .collapsed : .visible
        refreshScript(); refreshClock(); renderBand(); updateTextEditor()
    }
    func refreshScript() {
        if scriptRevision != self.document.revision {
            let cues = self.document.project.cues.sorted { $0.start < $1.start }
            let order = cues.map(\.id)
            if order != scriptOrder {
                script.children.clear(); scriptRows.removeAll(); scriptModels.removeAll(); scriptSelection = nil
                for cue in cues {
                    let header = label("", size: 11); header.fontFamily = FontFamily("Courier New")
                    let text = label("", size: 12); text.fontFamily = FontFamily("Courier New"); text.textWrapping = .wrap
                    let container = Border(); container.child = stack([header, text], spacing: 2)
                    let id = cue.id
                    container.tapped.addHandler { [weak self] _, _ in
                        guard let self, let current = self.document.project.cues.first(where: { $0.id == id }) else { return }
                        media.stop(); self.document.selection = current.id; self.document.track = current.track
                        seek(current.start); refreshScript()
                    }
                    script.children.append(container); scriptRows[cue.id] = (container, header, text)
                }
                scriptOrder = order
            }
            let rolesChanged = scriptRoles != self.document.project.roles || scriptFPS != fps
            let names = Dictionary(uniqueKeysWithValues: self.document.project.roles.map { ($0.id, $0.name) })
            for cue in cues {
                guard let row = scriptRows[cue.id], rolesChanged || scriptModels[cue.id] != cue else { continue }
                let name = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
                let header = Timecode.format(cue.start, fps: fps) + " — " + name + " :"
                if row.header.text != header { row.header.text = header }
                if row.text.text != cue.text { row.text.text = cue.text }
            }
            scriptModels = Dictionary(uniqueKeysWithValues: cues.map { ($0.id, $0) })
            scriptRoles = self.document.project.roles; scriptFPS = fps
            scriptRevision = self.document.revision
        }
        if scriptSelection != self.document.selection {
            if let previous = scriptSelection { scriptRows[previous]?.border.background = nil }
            if let current = self.document.selection { scriptRows[current]?.border.background = brush(0.2, 0.5, 1, alpha: 0.12) }
            scriptSelection = self.document.selection
        }
    }
    func refreshClock() {
        if displayedFrame != self.document.frame || displayedFPS != fps {
            timecode.text = Timecode.format(self.document.frame, fps: fps)
            displayedFrame = self.document.frame; displayedFPS = fps
        }
        let loop = self.document.currentLoop
        if displayedLoop != loop {
            loopLabel.text = loop.map { "boucle \($0.label)     \(Timecode.format($0.frame, fps: fps))" } ?? ""
            displayedLoop = loop
        }
        if displayedVI != media.usingVI {
            vo.opacity = media.usingVI ? 0.5 : 1; vi.opacity = media.usingVI ? 1 : 0.5
            displayedVI = media.usingVI
        }
    }
    func updatePlaybackRendering() {
        guard !isClosed else { return }
        lastTick = Date()
        lastRenderUptime = ProcessInfo.processInfo.systemUptime
        timelineClock.reset()
        if media.rate != 0, renderingSubscription == nil {
            renderingSubscription = CompositionTarget.rendering.addHandler { [weak self] _, _ in self?.tick() }
        } else if media.rate == 0 {
            renderingSubscription?.dispose(); renderingSubscription = nil
            refreshClock(); renderBand(reuse: true)
        }
    }
    func tick() {
        guard !isClosed else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, uptime - lastRenderUptime); lastRenderUptime = uptime
        if media.rate != 0 && !self.document.editing && !dialogShowing {
            if media.hasMedia && media.rate > 0 {
                let seconds = timelineClock.position(sample: media.position, rate: media.rate,
                    advancing: media.isAdvancing, now: uptime)
                playbackFrame = Double(self.document.project.mediaStartFrame) + seconds * Double(fps)
                self.document.frame = Int(playbackFrame!.rounded())
            } else {
                let next = (logicalFrame ?? Double(self.document.frame)) + elapsed * Double(fps) * media.rate
                logicalFrame = max(Double(self.document.project.mediaStartFrame), next)
                playbackFrame = logicalFrame
                self.document.frame = Int(logicalFrame!.rounded())
                if media.hasMedia { media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps)) }
            }
            refreshClock(); renderBand(reuse: true)
        } else { renderBand(reuse: true) }
    }
    func pollAutosave() {
        guard !isClosed else { return }
        let now = Date()
        if !dialogShowing && !isResizing && now.timeIntervalSince(lastAutosavePoll) >= 1 {
            lastAutosavePoll = now
            do { try self.document.autoSave(at: now) } catch { status.text = error.localizedDescription }
        }
    }
    func seek(_ frame: Int) {
        timelineClock.reset(); bandMotion.invalidate(); rulerMotion.invalidate()
        playbackFrame = nil
        self.document.frame = max(self.document.project.mediaStartFrame, frame)
        logicalFrame = Double(self.document.frame)
        media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
        refreshClock(); renderBand()
    }
    func showError(_ message: String) async { _ = await dialog("Cappella", content: label(message), primary: "OK") }
    func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { Task { @MainActor in await self.showError(error.localizedDescription) } }
    }
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
            dialog.maxWidth = width
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
    func mayReplace() async -> Bool {
        guard self.document.dirty else { return true }
        let result = await dialog("Enregistrer les modifications ?", content: label("Les modifications du projet courant seront perdues sans enregistrement."), primary: "Enregistrer", secondary: "Ne pas enregistrer", close: "Annuler")
        if result == .primary { return await save() }
        return result == .secondary
    }
    func attachPicker(_ picker: WinRTClass) throws {
        var stage: Int32 = 0
        let result = cappella_attach_picker(
            UnsafeMutableRawPointer(picker.thisPtr.pUnk.borrow), window.appWindow.id.value, &stage)
        guard result >= 0 else {
            let code = String(format: "0x%08X", UInt32(bitPattern: result))
            throw NSError(domain: "CappellaPicker", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: "Sélecteur Windows : échec du rattachement (étape \(stage), \(code))."
            ])
        }
    }
    func pickFile(_ extensions: [String], onError: ((String) -> Void)? = nil) async -> URL? {
        media.stop()
        do {
            let picker = FileOpenPicker(); for ext in extensions { picker.fileTypeFilter.append(ext) }; try attachPicker(picker)
            guard let file = try await picker.pickSingleFileAsync().get() else { return nil }
            return URL(fileURLWithPath: file.path)
        } catch {
            if let onError { onError(error.localizedDescription) }
            else { await showError(error.localizedDescription) }
            return nil
        }
    }
    func open(_ url: URL, recovery: Bool = false) async {
        if !recovery && self.document.url?.standardizedFileURL == url.standardizedFileURL { try? window.activate(); return }
        do {
            let project = try self.document.read(url)
            guard await mayReplace() else { return }
            unloadProjectMedia()
            self.document.replace(with: project, url: recovery ? nil : url)
            try loadProjectMedia()
            media.seek(Double(self.document.frame - project.mediaStartFrame) / Double(fps))
            refresh(); try window.activate()
        } catch { await showError(error.localizedDescription) }
    }
    func save(as saveAs: Bool = false, copy: Bool = false) async -> Bool {
        do {
            var destination = !saveAs && !copy ? self.document.url : nil
            if destination == nil {
                let picker = FileSavePicker()
                picker.fileTypeChoices.insert("Détection Cappella", [".detx"].toVector())
                picker.fileTypeChoices.insert("Projet Cappella", [".cappellaproject"].toVector())
                let name = self.document.url?.deletingPathExtension().lastPathComponent ?? self.document.project.title
                picker.suggestedFileName = copy ? self.document.preferences.copyName(for: name) : name
                try attachPicker(picker)
                if let file = try await picker.pickSaveFileAsync().get() { destination = URL(fileURLWithPath: file.path) }
            }
            guard let destination else { return false }
            try self.document.save(to: destination, copy: copy); return true
        } catch { await showError(error.localizedDescription); return false }
    }
}
