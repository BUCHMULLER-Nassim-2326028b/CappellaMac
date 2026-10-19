import Foundation
import WinUI
import WinAppSDK
import WindowsFoundation
import UWP
import WinSDK

@main
public final class CappellaWindowsApp: SwiftApplication {
    private var editor: WindowsEditor?
    private var instance: AppInstance?
    private var pendingFiles: [URL] = []
    private var openingFiles = false
    public required init() { super.init() }
    override public func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        MainActor.assumeIsolated {
            guard registerInstance() else { return }
            let editor = WindowsEditor(); self.editor = editor
            do { try editor.window.activate() } catch { print(error) }
            let files = CommandLine.arguments.dropFirst().filter { ["detx", "cappellaproject"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            enqueue(files.map { URL(fileURLWithPath: $0) })
            editor.recordSmokeState()
            recordActivationState()
        }
    }
    @MainActor
    private func registerInstance() -> Bool {
        do {
            let key = ProcessInfo.processInfo.environment["CAPPELLA_WINDOWS_INSTANCE_KEY"] ?? "Cappella.Editor.1"
            guard let instance = try AppInstance.findOrRegisterForKey(key) else { return true }
            self.instance = instance
            WindowsActivation.trace("registered current=\(instance.isCurrent)")
            if !instance.isCurrent {
                let arguments = try AppInstance.getCurrent().getActivatedEventArgs()
                WindowsActivation.trace("got arguments")
                Task { @MainActor in
                    do { WindowsActivation.trace("redirect start"); try await instance.redirectActivationToAsync(arguments).get(); WindowsActivation.trace("redirect finished") }
                    catch { print("Activation: \(error)") }
                    try? self.exit()
                }
                return false
            }
            instance.activated.addHandler { [weak self] _, args in
                WindowsActivation.trace("received activated")
                let commandLine = WindowsActivation.commandLine(from: args)
                let urls = WindowsActivation.files(in: commandLine)
                WindowsActivation.trace("parsed files=\(urls.count)")
                DispatchQueue.main.async { self?.enqueue(urls) }
            }
        } catch { print("Single instance: \(error)") }
        return true
    }
    @MainActor
    private func enqueue(_ urls: [URL]) {
        WindowsActivation.trace("enqueue \(urls.count)")
        pendingFiles.append(contentsOf: urls)
        guard let editor else { return }
        try? editor.window.activate()
        guard !openingFiles else { return }
        openingFiles = true
        Task { @MainActor in
            defer { openingFiles = false }
            while !pendingFiles.isEmpty {
                // A modal save/discard/cancel prompt must finish before the next file.
                while editor.dialogShowing { try? await Task.sleep(nanoseconds: 100_000_000) }
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
