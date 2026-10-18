import AppKit
import CappellaSession

/// The Window scene creates the one editor. File events only replace its session.
@MainActor
final class StartupDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FrenchMenus.install()
        if ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_MARKER"] == nil {
            AutomaticSaveController.shared.start()
            if ApplicationPreferences.load().checkUpdates { UpdateChecker.shared.check() }
        }
        DispatchQueue.main.async {
            if let path = ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_FIXTURE"] {
                if !ProjectSession.shared.open(URL(fileURLWithPath: path)) {
                    FileHandle.standardError.write(Data("Impossible d'ouvrir la fixture.\n".utf8))
                }
            }
            FrenchMenus.refresh()
        }
    }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        ProjectSession.shared.open(URL(fileURLWithPath: filename))
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if !ProjectSession.shared.open(URL(fileURLWithPath: filename)) { sender.reply(toOpenOrPrint: .cancel); return }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { ProjectSession.shared.showWindow() }
        return true
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
