import SwiftUI
import AppKit
import Darwin

@MainActor private final class TextModel: ObservableObject {
    @Published var text = "Merci maman."
    @Published var caret = 6
}
@MainActor private struct TextFixture: View {
    @ObservedObject var model: TextModel
    var body: some View { DialogueTextEditor(text: $model.text, caret: $model.caret).frame(width: 500, height: 50) }
}

@main
struct TimelineTextCheck {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "CappellaTextCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func waitFor(_ message: String, timeout: TimeInterval = 5, until ready: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !ready() {
            try require(Date() < deadline, message)
            // Yield to AppKit, Core Animation and SwiftUI; don't run a nested
            // CFRunLoop inside a synchronous test with an arbitrary 150ms delay.
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    @MainActor static func editor(in root: NSView?) -> DialogueTextEditor.FocusedTextView? {
        guard let root else { return nil }
        if let view = root as? DialogueTextEditor.FocusedTextView { return view }
        for child in root.subviews { if let view = editor(in: child) { return view } }
        return nil
    }
    @MainActor static func exercise() async throws {
        let application = NSApplication.shared
        let model = TextModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps: true)
        try await waitFor("Le runner n'a pas activé la fenêtre de test.") { window.isKeyWindow }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        var sheetEnded = false
        window.beginSheet(sheet) { _ in sheetEnded = true }
        try await waitFor("La feuille de choix du rôle n'est pas attachée.") { window.attachedSheet === sheet }
        window.contentView = NSHostingView(rootView: TextFixture(model: model))
        window.contentView?.layoutSubtreeIfNeeded()
        try await waitFor("L'éditeur n'a pas été créé dans la bande.") { editor(in: window.contentView) != nil }
        window.endSheet(sheet)
        try await waitFor("La feuille de choix du rôle ne s'est pas fermée.") { sheetEnded && window.attachedSheet == nil }
        sheet.orderOut(nil); window.makeKeyAndOrderFront(nil)
        do {
            try await waitFor("La bande n'a pas repris le clavier après la fermeture de la liste des rôles.") {
                guard let view = editor(in: window.contentView) else { return false }
                return window.isKeyWindow && window.firstResponder === view
            }
        } catch {
            let view = editor(in: window.contentView)
            let details = "active=\(application.isActive), running=\(application.isRunning), key=\(window.isKeyWindow), sheet=\(String(describing: window.attachedSheet)), responder=\(String(describing: window.firstResponder)), editorFrame=\(String(describing: view?.frame))\n"
            FileHandle.standardError.write(Data(details.utf8)); throw error
        }
        let view = editor(in: window.contentView)!
        try require(view.isEditable && view.isSelectable, "L'éditeur doit permettre la saisie et la sélection.")
        view.insertText("chère ", replacementRange: view.selectedRange())
        try await waitFor("La saisie accentuée ne modifie pas le projet à la position du curseur.") { model.text == "Merci chère maman." }
        view.setSelectedRange(NSRange(location: 6, length: 6))
        view.insertText("", replacementRange: view.selectedRange())
        try await waitFor("Remplacer une sélection ne modifie pas la même réplique.") { model.text == "Merci maman." }
        print("Texte sur bande : reprise du clavier après une feuille, saisie accentuée et remplacement de sélection vérifiés.")
    }
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        // NSApplication must dispatch activation, window and sheet events.
        // Let the async driver yield to its real event loop between assertions.
        DispatchQueue.main.async {
            Task { @MainActor in
                do { try await exercise(); Darwin.exit(0) }
                catch {
                    FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
                    Darwin.exit(1)
                }
            }
        }
        application.run()
    }
}
