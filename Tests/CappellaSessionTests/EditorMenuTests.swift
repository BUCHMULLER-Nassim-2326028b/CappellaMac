import AppKit
import XCTest
@testable import CappellaSession

/// Exercise the AppKit adapter in a GUI session without starting the editor.
/// Menu items owned by SwiftUI must retain their identity, order and count.
final class EditorMenuTests: XCTestCase {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "CappellaMenuCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor func testGeneratedMenusStayStable() async throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        let main = NSMenu()
        application.mainMenu = main
        func add(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title); main.addItem(item); return item
        }
        let file = add("File")
        let edit = add("Edit")
        let view = add("View")
        let window = add("Window")
        let display = add("Affichage")
        let help = add("Help")
        let originalItems = main.items.map(ObjectIdentifier.init)
        FrenchMenus.install()
        for iteration in 0..<300 {
            // Reproduce the system renaming/revalidating its generated items.
            view.title = iteration.isMultiple(of: 2) ? "View" : "Présentation"
            view.isHidden = false
            window.isHidden = false
            FrenchMenus.refresh()
            try Self.require(main.items.map(ObjectIdentifier.init) == originalItems, "Le correctif retire ou réinsère les menus système.")
            try Self.require(view.isHidden && window.isHidden, "Les menus système doivent rester masqués.")
            try Self.require(!display.isHidden && !file.isHidden && !edit.isHidden && !help.isHidden, "Les menus de Cappella doivent rester visibles.")
            try Self.require(file.title == "Fichier" && edit.title == "Édition" && help.title == "Aide", "Les menus doivent rester en français.")
            try Self.require(file.submenu!.items.filter { $0.title == "Fichiers récents" }.count == 1, "Le menu des fichiers récents est dupliqué.")
        }
        let lateView = add("Présentation")
        try Self.require(lateView.isHidden, "Un menu système ajouté après le lancement doit être masqué dès son ajout.")
        file.submenu = NSMenu(title: "File")
        FrenchMenus.refresh()
        try Self.require(file.submenu!.items.filter { $0.title == "Fichiers récents" }.count == 1, "Les fichiers récents doivent survivre au remplacement du menu Fichier.")
        print("Menus : identité et ordre conservés, menus système masqués, français et fichiers récents vérifiés.")
    }
}
