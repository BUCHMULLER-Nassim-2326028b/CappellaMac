import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore

extension UTType {
    static let cappellaProject = UTType(exportedAs: "org.cappella-rewrite.project", conformingTo: .json)
    static let detx = UTType(importedAs: "org.cappella-rewrite.detx", conformingTo: .xml)
}

struct ProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.detx, .cappellaProject] }
    var project: Project
    init(project: Project = Project()) { self.project = project }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        if configuration.contentType.conforms(to: .detx) { project = try DetX.read(data) }
        else { project = try Project.decode(data) }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        if configuration.contentType.conforms(to: .detx) { data = try DetX.write(project) }
        else { data = try project.encode() }
        return FileWrapper(regularFileWithContents: data)
    }
}

@main
struct CappellaMacApp: App {
    @NSApplicationDelegateAdaptor(StartupDelegate.self) private var startupDelegate

    init() { UserDefaults.standard.set(["fr"], forKey: "AppleLanguages") }

    var body: some Scene {
        DocumentGroup(newDocument: ProjectDocument()) { file in
            EditorView(project: file.$document.project)
                .frame(minWidth: 1000, minHeight: 620)
        }
        .defaultSize(width: 1420, height: 744)
        .commands {
            CappellaCommands()
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Cappella Mac") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Cappella Mac [BETA]",
                        .applicationVersion: "0.2.1",
                        .credits: NSAttributedString(string: "nvssgoat")
                    ])
                }
            }
            CommandGroup(replacing: .help) {
                Button("Documentation") { NSWorkspace.shared.open(URL(string: "https://cappella.app/")!) }
                    .keyboardShortcut(cappellaFunctionKey(1), modifiers: [])
                Button("Raccourcis clavier") {
                    let alert = NSAlert()
                    alert.messageText = "Raccourcis clavier"
                    alert.informativeText = "Entrée : saisir/valider directement sur la bande\nÉchap : annuler la phrase\nF2 : VO/VI\nEspace : lecture/pause\nHaut/Bas : lecture avant/arrière\nAlt+Gauche/Droite : une image\nGauche/Droite : signe précédent/suivant\nCtrl+Gauche/Droite : déplacer le signe\nCtrl+Alt+Gauche/Droite : déplacer son accroche\nF5–F8 : piste active ; Ctrl+F5–F8 : déplacer la phrase\nF9/F10 ou Tab/Maj+Tab : phrases\nF11/F12 : boucles\nF3 : recherche suivante ; F4 : vérifier\nCtrl+R : rôles ; Ctrl+F : recherche ; Ctrl+G : timecode\nCtrl+P : propriétés ; Ctrl+D : marquer une position\nCtrl+U : voix off ; Ctrl+Suppr : supprimer la phrase\nPavé numérique 0–9 : signes\nV/B/N/virgule : lecture lente\nPlus/Moins : zoom ; Ctrl+Plus/Moins : volume\nCtrl+* : couper le son\nLes commandes courantes acceptent aussi Cmd sur Mac."
                    alert.runModal()
                }
                Button("Page web de Cappella") { NSWorkspace.shared.open(URL(string: "https://cappella.app/")!) }
                Divider()
                Button("Rechercher des mises à jour") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases")!)
                }
                Divider()
                Button("Notes de version") { NSWorkspace.shared.open(URL(string: "https://cappella.app/historique.html")!) }
                Button("À propos de Cappella Mac") {
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Cappella Mac [BETA]", .applicationVersion: "0.2.1", .credits: NSAttributedString(string: "nvssgoat")])
                }
            }
        }
    }
}
