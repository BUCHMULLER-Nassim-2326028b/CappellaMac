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
                        .applicationVersion: "0.2.0",
                        .credits: NSAttributedString(string: "nvssgoat")
                    ])
                }
            }
            CommandGroup(replacing: .help) {
                Button("Raccourcis clavier de Cappella") {
                    let alert = NSAlert()
                    alert.messageText = "Raccourcis clavier"
                    alert.informativeText = "Espace : lecture/pause\nOption + flèches gauche/droite : une image\nFlèches gauche/droite : signe précédent/suivant\nF5 à F8 : pistes 1 à 4\nF9/F10 : phrases\nF11/F12 : boucles\nCmd+R : rôles\nCmd+F : recherche\nCmd+G : timecode\nDouble-clic sur une phrase : édition\nGlisser un signe dans la rythmo : déplacement"
                    alert.runModal()
                }
            }
        }
    }
}
