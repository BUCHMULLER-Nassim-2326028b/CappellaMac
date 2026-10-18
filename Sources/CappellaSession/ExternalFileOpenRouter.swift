import AppKit
import Foundation

/// Finder events can precede both didFinishLaunching and SwiftUI's first
/// window attachment. Keep them until that one editor can receive the file.
@MainActor
public final class ExternalFileOpenRouter {
    public static let shared = ExternalFileOpenRouter(session: .shared)
    private let session: ProjectSession
    private var windowOpener: (() -> Void)?
    private var launchFinished = false
    private var windowRequested = false
    private var wantsWindow = false
    private var scheduled = false
    private var processing = false
    private var pending: [URL] = []

    public init(session: ProjectSession) {
        self.session = session
        session.onWindowAttached = { [weak self] in self?.windowAttached() }
    }
    public func installWindowOpener(_ action: @escaping () -> Void) {
        windowOpener = action
        if launchFinished && wantsWindow { requestWindowIfNeeded() }
    }
    public func didFinishLaunching() {
        launchFinished = true
        showEditor()
    }
    public func open(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            if !pending.contains(normalized) { pending.append(normalized) }
        }
        guard !pending.isEmpty else { return }
        wantsWindow = true
        guard launchFinished else { return }
        requestWindowIfNeeded()
        scheduleDrain()
    }
    public func showEditor() {
        wantsWindow = true
        guard launchFinished else { return }
        requestWindowIfNeeded()
        scheduleDrain()
    }
    private func requestWindowIfNeeded() {
        if let window = session.window, window.isVisible || window.isMiniaturized {
            wantsWindow = false; windowRequested = false
            session.showWindow()
        } else if !windowRequested, let windowOpener {
            windowRequested = true
            // Let SwiftUI finish constructing its menu/scene graph first.
            DispatchQueue.main.async { windowOpener() }
        }
    }
    private func windowAttached() {
        guard wantsWindow || windowRequested || !pending.isEmpty else { return }
        windowRequested = false; wantsWindow = false
        scheduleDrain()
    }
    private func scheduleDrain() {
        guard launchFinished, session.window != nil, !scheduled, !processing else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }
    private func drain() {
        scheduled = false
        guard launchFinished, session.window != nil, !processing else { return }
        processing = true; windowRequested = false; wantsWindow = false
        defer { processing = false; recordTestState() }
        session.showWindow()
        while !pending.isEmpty {
            let url = pending.removeFirst()
            // Cancel stops the remaining batch, preserving the current work.
            if !session.open(url) { pending.removeAll(); break }
        }
    }
    private func recordTestState() {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_EXTERNAL_OPEN_TEST_STATE"] else { return }
        let state: [String: Any] = [
            "file": session.fileURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? "",
            "windows": session.visibleEditorWindowCount,
            "visible": session.window?.isVisible == true,
            "pid": ProcessInfo.processInfo.processIdentifier
        ]
        do { try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: path), options: .atomic) }
        catch { FileHandle.standardError.write(Data("External-open state: \(error)\n".utf8)) }
    }
}
