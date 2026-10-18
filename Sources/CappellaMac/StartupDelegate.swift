import AppKit

/// Keep DocumentGroup's save/open behavior, but start with an empty editor
/// rather than an Open panel when no document has been requested or restored.
final class StartupDelegate: NSObject, NSApplicationDelegate {
    private var openingSmokeFixture = false
    private var menuTimer: Timer?
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.showEditorIfNeeded(); FrenchMenus.refresh() }
        if menuTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in FrenchMenus.refresh() }
            RunLoop.main.add(timer, forMode: .common); menuTimer = timer
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        DispatchQueue.main.async { self.showEditorIfNeeded(); FrenchMenus.refresh() }
        if menuTimer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in FrenchMenus.refresh() }
            RunLoop.main.add(timer, forMode: .common); menuTimer = timer
        }
        return false
    }

    private func showEditorIfNeeded() {
        let controller = NSDocumentController.shared
        if let path = ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_FIXTURE"] {
            guard !openingSmokeFixture else { return }
            openingSmokeFixture = true
            controller.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, error in
                if let error { FileHandle.standardError.write(Data("Fixture: \(error)\n".utf8)) }
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            return
        }
        if !controller.documents.isEmpty {
            controller.documents.forEach { $0.showWindows() }
            return
        }
        do {
            _ = try controller.openUntitledDocumentAndDisplay(true)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } catch {
            NSApplication.shared.presentError(error)
        }
    }
}

/// Only enabled by the CI smoke test. A running process stuck at the Open panel
/// is insufficient: the editor must appear and complete its initial layout.
enum StartupSmokeCheck {
    static func recordEditorAppearance(cueCount: Int) {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_SMOKE_TEST_MARKER"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard NSApplication.shared.windows.contains(where: { $0.isVisible && $0.contentView != nil }) else { return }
            do {
                try "editor-visible:\(cueCount)\n".write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("Smoke test marker: \(error)\n".utf8))
            }
        }
    }
}
