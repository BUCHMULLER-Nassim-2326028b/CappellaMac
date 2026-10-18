import AppKit
import Combine
import UniformTypeIdentifiers
import CappellaCore

/// One editable project for the one main window. All entry points (menus,
/// recent files and Finder) use the same replacement/save transaction.
@MainActor
public final class ProjectSession: ObservableObject {
    public static let shared = ProjectSession()
    @Published public var project: Project { didSet { updateWindowTitle() } }
    @Published public private(set) var identity = UUID()
    @Published public private(set) var fileURL: URL?
    public weak var window: NSWindow?
    private let editorWindows = NSHashTable<NSWindow>.weakObjects()
    public var visibleEditorWindowCount: Int { editorWindows.allObjects.filter { $0.isVisible }.count }
    private var savedProject: Project
    private var terminating = false
    private var recoveredDocument = false
    private var automaticSnapshot: Project?
    private var lastAutomaticAttempt = Date()
    @Published public private(set) var lastAutomaticSaveURL: URL?
    @Published public private(set) var automaticSaveError: String?
    public var isModified: Bool { recoveredDocument || project != savedProject }
    public var windowTitle: String { (fileURL?.lastPathComponent ?? project.title) + " — Cappella" }

    // Deterministic substitutes for native dialogs in the regression tests.
    enum ReplacementChoice { case save, discard, cancel }
    var chooseReplacement: (() -> ReplacementChoice)?
    var chooseSaveDestination: (() -> URL?)?
    var reportFailure: ((Error) -> Void)?
    var recordRecent: (URL) -> Void = { NSDocumentController.shared.noteNewRecentDocumentURL($0) }

    public init(project: Project = Project()) {
        let normalized = Self.normalized(project)
        self.project = normalized; self.savedProject = normalized
    }

    private static func normalized(_ source: Project) -> Project {
        var value = source
        for i in value.cues.indices where value.cues[i].signs == nil { value.cues[i].signs = value.cues[i].anchors }
        return value
    }

    public func attach(window: NSWindow) {
        self.window = window; editorWindows.add(window)
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        guard let window else { return }
        let title = windowTitle
        if window.title != title { window.title = title }
        if window.isDocumentEdited != isModified { window.isDocumentEdited = isModified }
        if window.representedURL != fileURL { window.representedURL = fileURL }
    }

    public func showWindow() {
        window?.makeKeyAndOrderFront(nil); NSApp?.activate(ignoringOtherApps: true)
    }

    @discardableResult public func newProject() -> Bool {
        guard mayReplace() else { return false }
        replace(with: Project(), url: nil); return true
    }

    public func chooseOpen(backup: Bool = false) {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.detx, .cappellaProject]
        picker.allowsMultipleSelection = false
        if backup { picker.directoryURL = Self.automaticSaveDirectory; picker.title = "Ouvrir une sauvegarde" }
        guard picker.runModal() == .OK, let url = picker.url else { return }
        open(url, asRecovery: backup)
    }

    @discardableResult public func open(_ url: URL, asRecovery: Bool = false) -> Bool {
        if !asRecovery, url.standardizedFileURL == fileURL?.standardizedFileURL { showWindow(); return true }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // Decode first. A broken file must never discard the current work.
            let data = try Data(contentsOf: url)
            let next: Project
            if ["detx", "xml"].contains(url.pathExtension.lowercased()) { next = try DetX.read(data) }
            else { next = try Project.decode(data) }
            guard mayReplace() else { return false }
            replace(with: next, url: asRecovery ? nil : url)
            recoveredDocument = asRecovery; updateWindowTitle()
            if !asRecovery { recordRecent(url) }
            showWindow(); return true
        } catch { failure(error); return false }
    }

    private func replace(with value: Project, url: URL?) {
        // Commit/unmark the old native text view before its binding can point at
        // the replacement project, even when copied projects share cue IDs.
        window?.makeFirstResponder(nil)
        let next = Self.normalized(value)
        project = next; savedProject = next; fileURL = url; terminating = false
        recoveredDocument = false; automaticSnapshot = nil; lastAutomaticSaveURL = nil; automaticSaveError = nil; lastAutomaticAttempt = Date()
        identity = UUID(); updateWindowTitle()
    }

    @discardableResult public func save(as saveAs: Bool = false, copy: Bool = false) -> Bool {
        let responder = window?.firstResponder
        window?.makeFirstResponder(nil)
        defer { if let responder { window?.makeFirstResponder(responder) } }
        let destination: URL?
        if !saveAs, !copy, let fileURL { destination = fileURL }
        else if let chooseSaveDestination { destination = chooseSaveDestination() }
        else {
            let picker = NSSavePanel(); picker.allowedContentTypes = [.detx, .cappellaProject]
            let name = project.title.isEmpty ? "Sans titre" : project.title
            let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "\\", with: "-")
            let proposedName = fileURL?.lastPathComponent ?? safeName + ".detx"
            picker.nameFieldStringValue = copy ? ApplicationPreferences.load().copyName(for: proposedName) : proposedName
            destination = picker.runModal() == .OK ? picker.url : nil
        }
        guard let destination else { return false }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        do {
            let contents: Data
            if destination.pathExtension.lowercased() == "cappellaproject" { contents = try project.encode() }
            else { contents = try DetX.write(project) }
            try contents.write(to: destination, options: .atomic)
            if !copy { fileURL = destination; savedProject = project; recoveredDocument = false; recordRecent(destination); updateWindowTitle() }
            return true
        } catch { failure(error); return false }
    }

    public static var automaticSaveDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CappellaMac/Autosaves", isDirectory: true)
    }

    @discardableResult public func attemptAutomaticSave(at now: Date = Date(), preferences: ApplicationPreferences, in directory: URL? = nil) -> URL? {
        guard preferences.automaticSave else { lastAutomaticAttempt = now; return nil }
        guard now.timeIntervalSince(lastAutomaticAttempt) >= Double(min(120, max(1, preferences.saveInterval)) * 60),
              window?.attachedSheet == nil else { return nil }
        lastAutomaticAttempt = now
        return writeAutomaticBackup(in: directory)
    }

    /// Recovery copies never replace the source or clear its unsaved state.
    @discardableResult public func writeAutomaticBackup(in directory: URL? = nil) -> URL? {
        guard isModified, project != automaticSnapshot else { return nil }
        do {
            let folder = directory ?? Self.automaticSaveDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = fileURL?.deletingPathExtension().lastPathComponent ?? (project.title.isEmpty ? "Sans titre" : project.title)
            let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "\\", with: "-")
            let url = folder.appendingPathComponent(safe + "-" + identity.uuidString + ".cappellaproject")
            try project.encode().write(to: url, options: .atomic)
            automaticSnapshot = project; lastAutomaticSaveURL = url; automaticSaveError = nil
            return url
        } catch {
            automaticSaveError = "Sauvegarde automatique impossible : " + error.localizedDescription
            return nil
        }
    }

    private func mayReplace() -> Bool {
        guard isModified else { return true }
        let choice: ReplacementChoice
        if let chooseReplacement { choice = chooseReplacement() }
        else {
            let alert = NSAlert(); alert.messageText = "Enregistrer les modifications du projet ?"
            alert.informativeText = "Les modifications de « \(fileURL?.lastPathComponent ?? project.title) » seront perdues si vous ne les enregistrez pas."
            alert.addButton(withTitle: "Enregistrer")
            alert.addButton(withTitle: "Ne pas enregistrer")
            alert.addButton(withTitle: "Annuler").keyEquivalent = "\u{1b}"
            switch alert.runModal() {
            case .alertFirstButtonReturn: choice = .save
            case .alertSecondButtonReturn: choice = .discard
            default: choice = .cancel
            }
        }
        switch choice {
        case .save: return save()
        case .discard: return true
        case .cancel: return false
        }
    }

    public func requestClose() -> Bool { terminating || mayReplace() }
    public func approveWindowClose() { terminating = true }
    public func prepareToTerminate() -> Bool {
        guard !terminating else { return true }
        guard mayReplace() else { return false }
        terminating = true; return true
    }
    private func failure(_ error: Error) {
        if let reportFailure { reportFailure(error) } else { NSApp?.presentError(error) }
    }
}
