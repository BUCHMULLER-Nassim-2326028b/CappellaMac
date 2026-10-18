import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore

extension UTType {
    static let cappellaProject = UTType(exportedAs: "org.cappella-rewrite.project", conformingTo: .json)
    static let detx = UTType(importedAs: "org.cappella-rewrite.detx", conformingTo: .xml)
}

struct ProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cappellaProject] }
    var project: Project
    init(project: Project = Project()) { self.project = project }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        project = try Project.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try project.encode())
    }
}

@main
struct CappellaMacApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ProjectDocument()) { file in
            EditorView(project: file.$document.project)
                .frame(minWidth: 1050, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("À propos de Cappella Mac") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Cappella Mac — Réécriture expérimentale",
                        .applicationVersion: "0.1.0",
                        .credits: NSAttributedString(string: "Projet indépendant. Compatibilité Cappella/DetX en cours d'étude.")
                    ])
                }
            }
        }
    }
}
