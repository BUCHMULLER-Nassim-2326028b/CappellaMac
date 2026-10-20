import Foundation

/// A unique recovery file per opened project, with the same retry/interval rules.
public struct AutomaticBackup {
    public private(set) var identity = UUID()
    private var lastAttempt = Date()
    private var snapshot: Project?
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func due(at now: Date, preferences: ApplicationPreferences) -> Bool {
        guard preferences.automaticSave else { lastAttempt = now; return false }
        let interval = Double(min(120, max(1, preferences.saveInterval)) * 60)
        guard now.timeIntervalSince(lastAttempt) >= interval else { return false }
        lastAttempt = now
        return true
    }
    public mutating func write(_ project: Project, modified: Bool, fileURL: URL?, frame: Int?,
                               directory: URL) throws -> URL? {
        guard modified, project != snapshot else { return nil }
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? (project.title.isEmpty ? "Sans titre" : project.title)
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let safe = base.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        let name = safe.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let destination = directory.appendingPathComponent((name.isEmpty ? "Sans titre" : name) + "-" + identity.uuidString + ".cappellaproject")
        var copy = project
        if let frame { copy.lastPositionFrame = max(project.mediaStartFrame, frame) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try copy.encode().write(to: destination, options: .atomic)
        snapshot = project
        return destination
    }
}
