import Foundation
import CappellaCore

/// Windows presentation state; file formats and text/sign operations remain in
/// the same CappellaCore target used by the Mac application.
final class WindowsDocument {
    private(set) var revision: UInt64 = 0
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
    private var undoStates: [Project] = []
    private var redoStates: [Project] = []
    private var editingUndo: [Project]?
    private var editingRedo: [Project]?
    private var lastAutomaticSave = Date()
    private var automaticSnapshot: Project?
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
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    func replace(with next: Project, url: URL?) {
        project = next
        for index in project.cues.indices where project.cues[index].signs == nil { project.cues[index].signs = project.cues[index].anchors }
        saved = project; self.url = url; selection = nil; signSelection = nil
        track = 0; frame = project.lastPositionFrame ?? project.mediaStartFrame
        caret = 0; finishEditing()
        undoStates.removeAll(); redoStates.removeAll(); automaticSnapshot = nil; lastAutomaticSave = Date()
        changed?()
    }
    func read(_ url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        return ["detx", "xml"].contains(url.pathExtension.lowercased()) ? try DetX.read(data) : try Project.decode(data)
    }
    func save(to destination: URL, copy: Bool = false) throws {
        finishEditing()
        var snapshot = project; snapshot.lastPositionFrame = frame
        let data = destination.pathExtension.lowercased() == "cappellaproject" ? try snapshot.encode() : try DetX.write(snapshot)
        try data.write(to: destination, options: .atomic)
        if !copy { url = destination; project = snapshot; saved = snapshot }
        changed?()
    }
    func commit(recordUndo: Bool = true, _ change: (inout Project) throws -> Void) throws {
        var next = project
        try change(&next); try next.validate()
        guard next != project else { return }
        if recordUndo {
            textUndoCaptured = false
            undoStates.append(project)
            if undoStates.count > 200 { undoStates.removeFirst() }
        }
        redoStates.removeAll(); project = next; changed?()
    }
    func mutateCue(_ change: (inout Cue) throws -> Void) throws {
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        try commit { try change(&$0.cues[index]) }
    }
    func undo() {
        guard let value = undoStates.popLast() else { return }
        redoStates.append(project); project = value; finishEditing(); changed?()
    }
    func redo() {
        guard let value = redoStates.popLast() else { return }
        undoStates.append(project); project = value; finishEditing(); changed?()
    }
    func selectTrack(_ value: Int) { finishEditing(); track = min(3, max(0, value)); signSelection = nil; changed?() }
    func beginEditing(_ cue: Cue, at target: Int) {
        if selection != cue.id || !editing {
            finishEditing(); originalPhrase = cue; createdPhrase = false
            editingUndo = undoStates; editingRedo = redoStates; textUndoCaptured = false
        }
        selection = cue.id; track = cue.track; signSelection = nil
        caret = Timeline.textOffset(in: cue, at: target); editing = true; changed?()
    }
    func finishEditing() { textUndoCaptured = false; editing = false; originalPhrase = nil; createdPhrase = false; editingUndo = nil; editingRedo = nil }
    func cancelEditing() {
        if createdPhrase { project.cues.removeAll { $0.id == selection }; selection = nil }
        else if let originalPhrase, let index = project.cues.firstIndex(where: { $0.id == originalPhrase.id }) { project.cues[index] = originalPhrase }
        if let editingUndo { undoStates = editingUndo }
        if let editingRedo { redoStates = editingRedo }
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
        guard !project.cues.contains(where: { $0.track == track && $0.start <= frame && $0.end > frame }) else {
            throw ProjectError.invalid("Une phrase occupe déjà cette position sur la piste.")
        }
        let nextCue = project.cues.filter { $0.track == track && $0.start > frame }.map(\.start).min()
        let nextLoop = project.loops.filter { $0.frame > frame }.map(\.frame).min()
        let end = min(frame + project.framesPerSecond * 3, nextCue ?? Int.max, nextLoop ?? Int.max)
        var cue = Cue(roleID: role, start: frame, end: end, text: text); cue.track = track; cue.signs = cue.anchors
        finishEditing()
        let history = undoStates, future = redoStates
        try commit { $0.cues.append(cue) }
        editingUndo = history; editingRedo = future
        selection = cue.id; editing = edit; createdPhrase = true; originalPhrase = nil; caret = text.unicodeScalars.count; changed?()
    }
    func deletePhrase() throws { try commit { $0.cues.removeAll { $0.id == selection } }; selection = nil; signSelection = nil; finishEditing(); changed?() }
    func moveTrack(_ value: Int) throws {
        guard (0..<4).contains(value), let cue = selectedCue else { return }
        guard !project.cues.contains(where: { $0.id != cue.id && $0.track == value && $0.start < cue.end && $0.end > cue.start }) else {
            throw ProjectError.invalid("Une phrase occupe déjà la piste à cet endroit.")
        }
        try mutateCue { $0.track = value }; track = value; changed?()
    }
    func navigate(_ kind: String, _ direction: Int) -> Int? {
        finishEditing()
        let targets: [Int]
        switch kind {
        case "loop": targets = project.loops.map(\.frame)
        case "shot": targets = project.shots.map(\.frame)
        case "phrase": targets = project.cues.map(\.start)
        case "role": targets = project.cues.filter { $0.roleID == selectedCue?.roleID }.map(\.start)
        default: targets = Timeline.snapFrames(in: project)
        }
        guard let target = Timeline.adjacentFrame(in: targets.filter { $0 >= project.mediaStartFrame }, from: frame, direction: direction) else { return nil }
        frame = target; signSelection = nil
        if let cue = project.cues.first(where: { $0.anchors.contains { $0.frame == target } }) {
            selection = cue.id; track = cue.track; signSelection = cue.anchors.first { $0.frame == target }?.id
        }
        changed?(); return target
    }
    func addSign(_ kind: String) throws {
        if kind.hasPrefix("out_") {
            try mutateCue { cue in
                try cue.setBounds(start: cue.start, end: max(cue.start + 1, frame))
                var signs = cue.anchors; signs[signs.count - 1].kind = kind; cue.signs = signs
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
        guard preferences.automaticSave else { lastAutomaticSave = now; return }
        guard now.timeIntervalSince(lastAutomaticSave) >= Double(preferences.saveInterval * 60), dirty, project != automaticSnapshot else { return }
        let folder = directory ?? Self.backupDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = (url?.deletingPathExtension().lastPathComponent ?? "Sans titre").replacingOccurrences(of: ":", with: "-")
        var snapshot = project; snapshot.lastPositionFrame = frame
        try snapshot.encode().write(to: folder.appendingPathComponent(name + ".cappellaproject"), options: .atomic)
        automaticSnapshot = project; lastAutomaticSave = now
    }
    static var backupDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cappella/Autosaves")
    }
}
