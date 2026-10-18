import AppKit

/// SwiftUI owns the document/recent-file menus. Translate their generated items
/// by responder action, without replacing their native document behavior.
enum FrenchMenus {
    private static let recentTarget = RecentFilesTarget()
    static func refresh() {
        guard let main = NSApp.mainMenu else { return }
        NSApp.windowsMenu = nil
        for item in main.items {
            if ["View", "Window", "Présentation", "Fenêtre", "Fenêtres"].contains(item.title) {
                main.removeItem(item); continue
            }
            if item.title == "File" { item.title = "Fichier" }
            if item.title == "Edit" { item.title = "Édition" }
            if item.title == "Help" { item.title = "Aide" }
            if let menu = item.submenu {
                translate(menu)
                if item.title == "Fichier" { recentTarget.ensureMenu(in: menu) }
            }
        }
    }

    private static func translate(_ menu: NSMenu) {
        let names = [
            "newDocument:": "Nouveau", "openDocument:": "Ouvrir…", "clearRecentDocuments:": "Effacer le menu",
            "saveDocument:": "Enregistrer", "saveDocumentAs:": "Enregistrer sous…", "saveDocumentTo:": "Enregistrer une copie sous…",
            "performClose:": "Fermer", "revertDocumentToSaved:": "Rétablir la version enregistrée…",
            "undo:": "Annuler", "redo:": "Rétablir", "cut:": "Couper", "copy:": "Copier", "paste:": "Coller", "selectAll:": "Sélectionner tout",
            "terminate:": "Quitter Cappella", "hide:": "Masquer Cappella", "hideOtherApplications:": "Masquer les autres",
            "unhideAllApplications:": "Tout afficher", "printDocument:": "Imprimer…", "runPageLayout:": "Mise en page…"
        ]
        let titles = ["Open Recent":"Fichiers récents", "Open Recent…":"Fichiers récents", "Services":"Services",
            "Close":"Fermer", "File":"Fichier", "Edit":"Édition", "Help":"Aide",
            "Spelling and Grammar":"Orthographe et grammaire", "Substitutions":"Substitutions", "Transformations":"Transformations",
            "Speech":"Parole", "Start Speaking":"Commencer la lecture", "Stop Speaking":"Arrêter la lecture"]
        for item in menu.items {
            if let action = item.action, let name = names[NSStringFromSelector(action)] { item.title = name }
            else if let title = titles[item.title] { item.title = title }
            if let submenu = item.submenu { translate(submenu) }
        }
    }
}

private final class RecentFilesTarget: NSObject {
    private var paths: [URL] = []
    private var recentMenu: NSMenu?
    func ensureMenu(in fileMenu: NSMenu) {
        if recentMenu == nil {
            // Prefer the document system's menu if this SDK already creates it.
            guard !fileMenu.items.contains(where: { $0.title == "Fichiers récents" }) else { return }
            let item = NSMenuItem(title: "Fichiers récents", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: item.title); item.submenu = menu; fileMenu.addItem(item); recentMenu = menu
        }
        let urls = NSDocumentController.shared.recentDocumentURLs
        guard let menu = recentMenu, urls != paths || menu.items.isEmpty else { return }
        paths = urls; menu.removeAllItems()
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; menu.addItem(item)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Effacer le menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared; menu.addItem(clear)
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
