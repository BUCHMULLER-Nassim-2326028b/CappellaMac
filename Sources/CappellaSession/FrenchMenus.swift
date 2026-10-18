import AppKit

/// SwiftUI owns the document/recent-file menus. Translate their generated items
/// by responder action, without replacing their native document behavior.
public enum FrenchMenus {
    private static let recentTarget = RecentFilesTarget()
    private static var observers: [NSObjectProtocol] = []
    private static var refreshing = false

    public static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let menu = notification.object as? NSMenu, menu === NSApp.mainMenu else { return }
                refresh()
            })
        }
        observers.append(center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { _ in refresh() })
        refresh()
    }
    public static func refresh() {
        guard !refreshing, let main = NSApp.mainMenu else { return }
        refreshing = true
        defer { refreshing = false }
        for item in main.items {
            if ["View", "Window", "Présentation", "Fenêtre", "Fenêtres"].contains(item.title) {
                // Keep SwiftUI's items in place. Removing them causes it to
                // reinsert them, making the menu bar blink during playback.
                if !item.isHidden { item.isHidden = true }
                continue
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
            if let action = item.action, let name = names[NSStringFromSelector(action)], item.title != name { item.title = name }
            else if let title = titles[item.title], item.title != title { item.title = title }
            if let submenu = item.submenu { translate(submenu) }
        }
    }
}

private final class RecentFilesTarget: NSObject {
    private var paths: [URL] = []
    private var recentMenu: NSMenu?
    private weak var owner: NSMenu?
    func ensureMenu(in fileMenu: NSMenu) {
        if owner !== fileMenu { owner = fileMenu; recentMenu = nil; paths = [] }
        if let header = fileMenu.items.first(where: { $0.title == "Fichiers récents" }),
           let recentMenu, header.submenu !== recentMenu { self.recentMenu = nil; paths = [] }
        if recentMenu == nil {
            // Reuse the header, but own its actions: a native document-controller
            // submenu would bypass the single-window replacement transaction.
            let item: NSMenuItem
            if let existing = fileMenu.items.first(where: { $0.title == "Fichiers récents" }) { item = existing }
            else {
                item = NSMenuItem(title: "Fichiers récents", action: nil, keyEquivalent: "")
                fileMenu.addItem(item)
            }
            let menu = NSMenu(title: item.title); item.submenu = menu; recentMenu = menu
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
        DispatchQueue.main.async { ProjectSession.shared.open(url) }
    }
}
