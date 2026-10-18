import AppKit
import Foundation
import Darwin

/// Exercise Launch Services, exactly like Finder: cold launch, another file
/// while running, then the same file again. No fixture-loading shortcut.
@main
struct FinderOpenCheck {
    struct State: Decodable {
        let file: String
        let windows: Int
        let visible: Bool
        let pid: Int32
    }
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "CappellaFinderCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func open(_ file: URL, app: URL, environment: [String: String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = environment
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: configuration) { running, error in
                if let error { continuation.resume(throwing: error) }
                else if let running { continuation.resume(returning: running) }
                else { continuation.resume(throwing: NSError(domain: "CappellaFinderCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Launch Services n'a pas démarré l'application."])) }
            }
        }
    }
    @MainActor static func waitForState(_ path: URL, file: URL, app: NSRunningApplication) async throws {
        let deadline = Date().addingTimeInterval(30)
        while true {
            try require(!app.isTerminated, "L'application s'est fermée pendant l'ouverture Finder.")
            if let data = try? Data(contentsOf: path), let state = try? JSONDecoder().decode(State.self, from: data), state.file == file.resolvingSymlinksInPath().standardizedFileURL.path {
                try require(state.pid == app.processIdentifier, "Le fichier a été ouvert dans un autre processus.")
                try require(state.visible && state.windows == 1, "Finder doit afficher exactement une fenêtre principale.")
                return
            }
            try require(Date() < deadline, "Le fichier Finder n'a pas atteint une fenêtre visible : \(file.lastPathComponent).")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    @MainActor static func exercise() async throws {
        try require(CommandLine.arguments.count == 3, "Arguments : application.app fixture.detx")
        let app = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let fixture = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-Finder-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("Épisode #107 au lancement.detx")
        let next = directory.appendingPathComponent("Épisode #108 app ouverte.detx")
        try FileManager.default.copyItem(at: fixture, to: first)
        try FileManager.default.copyItem(at: fixture, to: next)
        let state = directory.appendingPathComponent("finder-state.json")
        let environment = [
            "CAPPELLA_EXTERNAL_OPEN_TEST_STATE": state.path,
            "CAPPELLA_SMOKE_TEST_MARKER": directory.appendingPathComponent("editor-ready.txt").path
        ]
        let running = try await open(first, app: app, environment: environment)
        defer { running.terminate() }
        try await waitForState(state, file: first, app: running)
        try FileManager.default.removeItem(at: state)
        let reopened = try await open(next, app: app, environment: environment)
        try require(reopened.processIdentifier == running.processIdentifier, "L'ouverture d'un autre fichier ne doit pas relancer l'application.")
        try await waitForState(state, file: next, app: running)
        try FileManager.default.removeItem(at: state)
        _ = try await open(next, app: app, environment: environment)
        try await waitForState(state, file: next, app: running)
        // Stay alive through the following AppKit/SwiftUI scene updates too.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try require(!running.isTerminated, "L'application s'est fermée après la livraison du fichier.")
        print("Finder : lancement par fichier, ouverture à chaud et réouverture identique dans une seule fenêtre vérifiés.")
    }
    @MainActor static func main() {
        let application = NSApplication.shared
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
