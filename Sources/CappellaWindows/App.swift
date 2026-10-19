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

extension WindowsEditor {
    func recordSmokeState() {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_SMOKE_MARKER"] else { return }
        let timer = DispatcherTimer(); timer.interval = TimeSpan(duration: 10_000_000)
        var testFrame: Int?
        timer.tick.addHandler { [weak self, timer] _, _ in
            guard let self else { return }
            var editingWorks = true
            if let cue = self.document.project.cues.first {
                if testFrame == nil {
                    testFrame = self.document.frame
                    self.document.beginEditing(cue, at: cue.start)
                    updateTextEditor(focus: true)
                    textEditor?.text = "Vérification é🙂 — saisie sur la bande."
                    return // TextChanged is delivered asynchronously by WinUI.
                }
                editingWorks = self.document.selectedCue?.text == "Vérification é🙂 — saisie sur la bande." && textEditor != nil && self.document.frame == testFrame
                self.document.cancelEditing(); updateTextEditor()
            }
            try? timer.stop()
            let state: [String: Any] = ["visible": window.visible, "title": self.document.project.title,
                "cues": self.document.project.cues.count, "pid": ProcessInfo.processInfo.processIdentifier,
                "layoutWidth": root.actualWidth, "bandElements": band.children.size + bandBackdrop.children.size, "scriptRows": scriptRows.count, "editingWorks": editingWorks]
            do { try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: path), options: .atomic) }
            catch { print(error) }
        }
        try? timer.start()
    }
}

enum WindowsActivation {
    static func trace(_ message: String) {
        guard let marker = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_ACTIVATION_MARKER"] else { return }
        let path = marker + "." + String(ProcessInfo.processInfo.processIdentifier) + ".log"
        let data = Data((message + "\n").utf8)
        if let file = FileHandle(forWritingAtPath: path) {
            defer { try? file.close() }; _ = try? file.seekToEnd(); try? file.write(contentsOf: data)
        } else { try? data.write(to: URL(fileURLWithPath: path)) }
    }
    static func commandLine(from arguments: AppActivationArguments?) -> String {
        // Desktop activation supplies an interface projection, not necessarily
        // the UWP concrete LaunchActivatedEventArgs runtime class.
        (arguments?.data as? any UWP.ILaunchActivatedEventArgs)?.arguments ?? ""
    }
    static func files(in commandLine: String) -> [URL] {
        var count: Int32 = 0
        let arguments = commandLine.withCString(encodedAs: UTF16.self) { CommandLineToArgvW($0, &count) }
        guard let arguments else { return [] }
        defer { _ = LocalFree(arguments) }
        return (0..<Int(count)).compactMap { index in
            guard let argument = arguments[index] else { return nil }
            let path = String(decodingCString: argument, as: UTF16.self)
            let url = URL(fileURLWithPath: path)
            return ["detx", "cappellaproject"].contains(url.pathExtension.lowercased()) ? url : nil
        }
    }
}
