import Foundation
import CappellaCore

/// Windows presentation state; file formats and text/sign operations remain in
/// the same CappellaCore target used by the Mac application.
final class WindowsDocument {
    private(set) var revision: UInt64 = 0
    private(set) var identity = UUID()
    private var sortedLoops: [Marker] = []
    private var cachedDirty: Bool?
    var project = Project() {
        didSet {
            revision &+= 1
            cachedDirty = nil
            if oldValue.loops != project.loops { sortedLoops = project.loops.sorted { $0.frame < $1.frame } }
        }
    }
    private var saved = Project() { didSet { cachedDirty = nil } }
    private(set) var url: URL?
    var selection: UUID?
    var signSelection: UUID?
    var track = 0
    var frame = 0
    var caret = 0
    var editing = false
    private var textUndoCaptured = false
    var originalPhrase: Cue?
    var createdPhrase = false
    var preferences = ApplicationPreferences.load()
    private var history = ProjectHistory()
    private var backup = AutomaticBackup()
    var changed: (() -> Void)?
    var dirty: Bool {
        if let cachedDirty { return cachedDirty }
        let value = project != saved
        cachedDirty = value
        return value
    }
    var selectedCue: Cue? { project.cues.first { $0.id == selection } }
    var currentLoop: Marker? {
        var low = 0, high = sortedLoops.count
        while low < high {
            let middle = low + (high - low) / 2
            if sortedLoops[middle].frame <= frame { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? sortedLoops[low - 1] : nil
    }
    func nextLoop(after frame: Int) -> Marker? {
        var low = 0, high = sortedLoops.count
        while low < high {
            let middle = low + (high - low) / 2
            if sortedLoops[middle].frame <= frame { low = middle + 1 } else { high = middle }
        }
        return low < sortedLoops.count ? sortedLoops[low] : nil
    }
    var title: String { (url?.lastPathComponent ?? project.title) + (dirty ? " *" : "") + " - Cappella" }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func replace(with next: Project, url: URL?) {
        identity = UUID()
        project = ProjectEditing.normalized(next)
        saved = project; self.url = url; selection = nil; signSelection = nil
        track = 0; frame = project.lastPositionFrame ?? project.mediaStartFrame
        caret = 0; finishEditing()
        history.reset(); backup.reset()
        changed?()
    }
    func read(_ url: URL) throws -> Project {
        try ProjectFile.read(url)
    }
    func save(to destination: URL, copy: Bool = false) throws {
        finishEditing()
        var snapshot = project; snapshot.lastPositionFrame = frame
        try ProjectFile.write(snapshot, to: destination)
        if !copy { url = destination; project = snapshot; saved = snapshot }
        changed?()
    }
    func commit(recordUndo: Bool = true, _ change: (inout Project) throws -> Void) throws {
        var next = project
        try change(&next); try next.validate()
        guard next != project else { return }
        history.record(before: project, after: next, enabled: recordUndo)
        if recordUndo { textUndoCaptured = false }
        project = next; changed?()
    }
    func mutateCue(_ change: (inout Cue) throws -> Void) throws {
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        try commit { try change(&$0.cues[index]) }
    }
    func undo() {
        guard let value = history.undo(project) else { return }
        project = value; finishEditing()
        if !project.cues.contains(where: { $0.id == selection }) { selection = nil; signSelection = nil }
        changed?()
    }
    func redo() {
        guard let value = history.redo(project) else { return }
        project = value; finishEditing()
        if !project.cues.contains(where: { $0.id == selection }) { selection = nil; signSelection = nil }
        changed?()
    }
    func selectTrack(_ value: Int) {
        finishEditing(); track = min(3, max(0, value)); signSelection = nil
        selection = project.cues.last(where: { $0.track == track && $0.start <= frame && $0.end >= frame })?.id
        changed?()
    }
    func beginEditing(_ cue: Cue, at target: Int) {
        if selection != cue.id || !editing {
            finishEditing(); originalPhrase = cue; createdPhrase = false
            history.beginGroup(project); textUndoCaptured = false
        }
        selection = cue.id; track = cue.track; signSelection = nil
        caret = Timeline.textOffset(in: cue, at: target); editing = true; changed?()
    }
    func finishEditing() { textUndoCaptured = false; editing = false; originalPhrase = nil; createdPhrase = false; history.endGroup() }
    func cancelEditing() {
        if let value = history.cancelGroup() { project = value }
        if !project.cues.contains(where: { $0.id == selection }) { selection = nil; signSelection = nil }
        finishEditing(); changed?()
    }
    func setText(_ text: String, caret: Int) throws {
        self.caret = caret
        guard let index = project.cues.firstIndex(where: { $0.id == selection }), project.cues[index].text != text else { return }
        // Keep one undo snapshot for consecutive typing within this editing session.
        try commit(recordUndo: !editing || !textUndoCaptured) { $0.cues[index].editText(text) }
        if editing { textUndoCaptured = true }
    }
    func createPhrase(role: UUID, text: String = "", edit: Bool = true) throws {
        finishEditing()
        history.beginGroup(project)
        var created: Cue?
        do { try commit { created = try ProjectEditing.createPhrase(in: &$0, role: role, frame: frame, track: track, text: text) } }
        catch { _ = history.cancelGroup(); throw error }
        guard let cue = created else { return }
        selection = cue.id; editing = edit; createdPhrase = true; originalPhrase = nil; caret = text.unicodeScalars.count; changed?()
    }
    func deletePhrase() throws {
        try commit { ProjectEditing.deletePhrase(in: &$0, id: selection) }
        selection = nil; signSelection = nil; finishEditing(); changed?()
    }
    func moveTrack(_ value: Int) throws {
        guard let id = selection else { return }
        try commit { try ProjectEditing.movePhrase(in: &$0, id: id, track: value) }
        track = value; changed?()
    }
    func navigate(_ kind: String, _ direction: Int, mediaDuration: Double = 0) -> Int? {
        finishEditing()
        guard let destination = ControlNavigation.destination(in: project, kind: kind, direction: direction,
            from: frame, selection: selection, mediaDuration: mediaDuration) else { return nil }
        frame = destination.frame; signSelection = destination.signID
        if let id = destination.cueID, let destinationTrack = destination.track {
            selection = id; track = destinationTrack
        }
        changed?(); return destination.frame
    }
    func addSign(_ kind: String) throws {
        if kind.hasPrefix("out_") {
            if let id = selection {
                try commit { try ProjectEditing.finalizePhrase(in: &$0, id: id, frame: frame, kind: kind) }
            }
            finishEditing(); changed?(); return
        }
        try mutateCue { cue in
            try Timeline.addSign(to: &cue, kind: kind, frame: frame, textOffset: editing ? caret : Timeline.textOffset(in: cue, at: frame))
            signSelection = cue.signs?.first { $0.frame == frame && $0.kind == kind }?.id
        }
    }
    func removeSign() throws {
        guard let cue = selectedCue, let id = signSelection,
              let index = cue.anchors.firstIndex(where: { $0.id == id }), index > 0, index < cue.anchors.count - 1 else { return }
        try mutateCue { $0.signs?.removeAll { $0.id == id } }; signSelection = nil
    }
    func autoSave(at now: Date = Date(), using supplied: ApplicationPreferences? = nil, in directory: URL? = nil) throws {
        if let supplied { preferences = supplied }
        guard backup.due(at: now, preferences: preferences) else { return }
        _ = try backup.write(project, modified: dirty, fileURL: url, frame: frame, directory: directory ?? Self.backupDirectory)
    }
    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cappella/Autosaves")
    }
}
