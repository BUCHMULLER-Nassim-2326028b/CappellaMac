import Foundation
import WinUI
import WinAppSDK
import WindowsFoundation
import UWP
import WinSDK

@main
public final class CappellaWindowsApp: SwiftApplication {
    private var editor: WindowsEditor?
    private var openingTask: Task<Void, Never>?
    private var pendingFiles: [URL] = []
    private var openingFiles = false
    public required init() { super.init() }
    override public func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        MainActor.assumeIsolated {
            let editor = WindowsEditor(); self.editor = editor
            editor.onClosed = { [weak self] in
                self?.openingTask?.cancel(); self?.openingTask = nil
                self?.pendingFiles.removeAll(); self?.editor = nil
                try? self?.exit()
                // The custom desktop message pump must also be told to stop.
                PostQuitMessage(0)
            }
            do { try editor.window.activate() } catch { print(error) }
            let files = CommandLine.arguments.dropFirst().filter { ["detx", "cappellaproject"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            enqueue(files.map { URL(fileURLWithPath: $0) })
            if editor.document.preferences.showControlAtLaunch { editor.showProjection() }
            editor.recordSmokeState()
            recordActivationState()
        }
    }
    override public func preTranslateMessage(_ message: UnsafePointer<MSG>) -> Bool {
        MainActor.assumeIsolated { editor?.handleDesktopMessage(message.pointee) ?? false }
    }
    @MainActor
    private func enqueue(_ urls: [URL]) {
        WindowsActivation.trace("enqueue \(urls.count)")
        pendingFiles.append(contentsOf: urls)
        guard let editor else { return }
        try? editor.window.activate()
        guard !openingFiles else { return }
        openingFiles = true
        openingTask = Task { @MainActor in
            defer { openingFiles = false; openingTask = nil }
            while !pendingFiles.isEmpty && !Task.isCancelled && !editor.isClosed {
                // A modal save/discard/cancel prompt must finish before the next file.
                while editor.dialogShowing && !Task.isCancelled && !editor.isClosed { try? await Task.sleep(nanoseconds: 100_000_000) }
                guard !Task.isCancelled, !editor.isClosed else { return }
                await editor.open(pendingFiles.removeFirst())
                recordActivationState()
            }
        }
    }
    @MainActor
    private func recordActivationState() {
        guard let editor, let path = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_ACTIVATION_MARKER"] else { return }
        let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "cues": editor.document.project.cues.count,
            "title": editor.document.project.title, "visible": editor.window.visible]
        try? JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
