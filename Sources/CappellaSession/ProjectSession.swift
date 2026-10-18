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
    public var isModified: Bool { project != savedProject }
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

    public func chooseOpen() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.detx, .cappellaProject]
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        open(url)
    }

    @discardableResult public func open(_ url: URL) -> Bool {
        if url.standardizedFileURL == fileURL?.standardizedFileURL { showWindow(); return true }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // Decode first. A broken file must never discard the current work.
            let data = try Data(contentsOf: url)
            let next: Project
            if ["detx", "xml"].contains(url.pathExtension.lowercased()) { next = try DetX.read(data) }
            else { next = try Project.decode(data) }
            guard mayReplace() else { return false }
            replace(with: next, url: url); recordRecent(url); showWindow(); return true
        } catch { failure(error); return false }
    }

    private func replace(with value: Project, url: URL?) {
        // Commit/unmark the old native text view before its binding can point at
        // the replacement project, even when copied projects share cue IDs.
        window?.makeFirstResponder(nil)
        let next = Self.normalized(value)
        project = next; savedProject = next; fileURL = url; terminating = false
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
            picker.nameFieldStringValue = fileURL?.lastPathComponent ?? safeName + ".detx"
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
            if !copy { fileURL = destination; savedProject = project; recordRecent(destination); updateWindowTitle() }
            return true
        } catch { failure(error); return false }
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
