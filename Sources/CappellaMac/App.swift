import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore
import CappellaSession

@main
@MainActor
struct CappellaMacApp: App {
    @NSApplicationDelegateAdaptor(StartupDelegate.self) private var startupDelegate
    @StateObject private var session = ProjectSession.shared

    init() { UserDefaults.standard.set(["fr"], forKey: "AppleLanguages") }

    var body: some Scene {
        Window("Cappella", id: "editor") {
            EditorView(project: $session.project)
                .id(session.identity)
                .frame(minWidth: 1000, minHeight: 620)
                .background(EditorWindowBridge(session: session).frame(width: 0, height: 0))
                .navigationTitle(session.windowTitle)
        }
        .defaultSize(width: 1420, height: 744)
        .commands {
            CappellaCommands()
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Cappella") { AppBranding.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Button("Documentation") { NSWorkspace.shared.open(URL(string: "https://cappella.app/")!) }
                    .keyboardShortcut(cappellaFunctionKey(1), modifiers: [])
                Button("Raccourcis clavier") {
                    let alert = NSAlert()
                    alert.messageText = "Raccourcis clavier"
                    alert.informativeText = "Entrée : saisir/valider directement sur la bande\nÉchap : annuler la phrase\nF2 : VO/VI\nEspace : lecture/pause\nHaut/Bas : lecture avant/arrière\nAlt+Gauche/Droite : une image\nGauche/Droite : signe précédent/suivant\nCtrl+Gauche/Droite : déplacer le signe\nCtrl+Alt+Gauche/Droite : déplacer son accroche\nCtrl+Haut/Bas : piste précédente/suivante\nF5–F8 : piste active ; Ctrl+F5–F8 : déplacer la phrase\nF9/F10 ou Tab/Maj+Tab : phrases\nF11/F12 : boucles\nF3 : recherche suivante ; F4 : vérifier\nCtrl+R : rôles ; Ctrl+F : recherche ; Ctrl+G : timecode\nCtrl+P : propriétés ; Ctrl+D : marquer une position\nCtrl+U : voix off / hors champ (souligné) ; Ctrl+Suppr : supprimer la phrase\nPavé numérique 0–9 : signes\nV/B/N/virgule : lecture lente\nPlus/Moins : zoom ; Ctrl+Plus/Moins : volume\nCtrl+* : couper le son\nLes commandes courantes acceptent aussi Cmd sur Mac."
                    alert.runModal()
                }
                Button("Page web de Cappella") { NSWorkspace.shared.open(URL(string: "https://cappella.app/")!) }
                Divider()
                Button("Rechercher des mises à jour") {
                    UpdateChecker.shared.check(userInitiated: true)
                }
                Divider()
                Button("Notes de version") { NSWorkspace.shared.open(URL(string: "https://cappella.app/historique.html")!) }
                Button("À propos de Cappella") { AppBranding.showAbout() }
            }
        }
    }
}
