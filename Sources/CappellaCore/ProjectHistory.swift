import Foundation

/// One history for project edits, independent of native text/undo frameworks.
public struct ProjectHistory {
    private var past: [Project] = []
    private var future: [Project] = []
    private var group: (project: Project, past: [Project], future: [Project])?
    private var groupRecorded = false
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func reset() { self = Self() }
    public mutating func beginGroup(_ project: Project) {
        guard group == nil else { return }
        group = (project, past, future); groupRecorded = false
    }
    public mutating func endGroup() { group = nil; groupRecorded = false }
    public mutating func cancelGroup() -> Project? {
        guard let group else { return nil }
        past = group.past; future = group.future
        let project = group.project; endGroup()
        return project
    }
    public mutating func record(before: Project, after: Project, enabled: Bool = true) {
        guard before != after else { return }
        if enabled && !(group != nil && groupRecorded) {
            past.append(before)
            if past.count > 200 { past.removeFirst(past.count - 200) }
            if group != nil { groupRecorded = true }
        }
        future.removeAll()
    }
    public mutating func undo(_ current: Project) -> Project? {
        endGroup()
        guard let value = past.popLast() else { return nil }
        future.append(current); return value
    }
    public mutating func redo(_ current: Project) -> Project? {
        endGroup()
        guard let value = future.popLast() else { return nil }
        past.append(current); return value
    }
}

public enum ProjectFile {
    public static func read(_ url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        let value = ["detx", "xml"].contains(url.pathExtension.lowercased()) ? try DetX.read(data) : try Project.decode(data)
        return ProjectEditing.normalized(value)
    }
    public static func write(_ project: Project, to url: URL) throws {
        let data = url.pathExtension.lowercased() == "cappellaproject" ? try project.encode() : try DetX.write(project)
        try data.write(to: url, options: .atomic)
    }
}
