import AppKit
import CappellaSession

/// The Window scene creates the one editor. File events only replace its session.
@MainActor
final class StartupDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppBranding.install()
        FrenchMenus.install()
        if ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_MARKER"] == nil {
            AutomaticSaveController.shared.start()
            if ApplicationPreferences.load().checkUpdates { UpdateChecker.shared.check() }
        }
        DispatchQueue.main.async {
            ExternalFileOpenRouter.shared.didFinishLaunching()
            if let path = ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_FIXTURE"] {
                if !ProjectSession.shared.open(URL(fileURLWithPath: path)) {
                    FileHandle.standardError.write(Data("Impossible d'ouvrir la fixture.\n".utf8))
                }
            }
            FrenchMenus.refresh()
        }
    }
    // Implement the URL-based AppKit entry point exclusively. Mixing it with
    // SwiftUI onOpenURL on a unique Window can replace/close the current scene.
    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalFileOpenRouter.shared.open(urls)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        ExternalFileOpenRouter.shared.showEditor()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // macOS 26 can temporarily close a scene while delivering a Finder file.
        // The window delegate approves actual user closes after save/cancel.
        ProjectSession.shared.shouldTerminateAfterLastWindowClosed
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ProjectSession.shared.prepareToTerminate() ? .terminateNow : .terminateCancel
    }
}

/// Only enabled by the CI smoke test. A running process stuck at the Open panel
/// is insufficient: the editor must appear and complete its initial layout.
enum StartupSmokeCheck {
    static func recordEditorAppearance(cueCount: Int) {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_MARKER"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard ProjectSession.shared.visibleEditorWindowCount == 1 else { return }
            let count = ProjectSession.shared.project.cues.count
            do {
                try "editor-visible:\(count)\n".write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("Smoke test marker: \(error)\n".utf8))
            }
        }
    }
}
