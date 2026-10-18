import SwiftUI
import AppKit

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
    @MainActor static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
    @MainActor static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let model = TextModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps: true)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet, completionHandler: nil)
        window.contentView = NSHostingView(rootView: TextFixture(model: model))
        settle()
        window.endSheet(sheet); sheet.orderOut(nil); window.makeKeyAndOrderFront(nil); settle()
        guard let view = window.firstResponder as? DialogueTextEditor.FocusedTextView else {
            throw NSError(domain: "CappellaTextCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "La bande n'a pas repris le clavier après la fermeture de la liste des rôles."])
        }
        try require(view.isEditable && view.isSelectable, "L'éditeur doit permettre la saisie et la sélection.")
        view.insertText("chère ", replacementRange: view.selectedRange()); settle()
        try require(model.text == "Merci chère maman.", "La saisie accentuée doit modifier le projet à la position du curseur.")
        view.setSelectedRange(NSRange(location: 6, length: 6))
        view.insertText("", replacementRange: view.selectedRange()); settle()
        try require(model.text == "Merci maman.", "Remplacer une sélection doit modifier la même réplique.")
        window.close()
        print("Texte sur bande : reprise du clavier après une feuille, saisie accentuée et remplacement de sélection vérifiés.")
    }
}
