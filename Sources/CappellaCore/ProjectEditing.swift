import Foundation

/// Validated project mutations shared by the native editors.
public enum ProjectEditing {
    public static let phraseClipboardType = "org.cappella.phrase"
    public static func normalized(_ source: Project) -> Project {
        var project = source
        for index in project.cues.indices where project.cues[index].signs == nil {
            project.cues[index].signs = project.cues[index].anchors
        }
        return project
    }
    public static func createPhrase(in project: inout Project, role: UUID, frame: Int, track: Int,
                                    text: String = "", kind: String = "in_open") throws -> Cue {
        guard project.roles.contains(where: { $0.id == role }), (0..<4).contains(track),
              frame >= project.mediaStartFrame, kind.hasPrefix("in_") else { throw ProjectError.invalid("Rôle, piste ou position invalide.") }
        guard !project.cues.contains(where: { $0.track == track && $0.start <= frame && $0.end > frame }) else {
            throw ProjectError.invalid("Une phrase occupe déjà cette position sur la piste.")
        }
        let nextCue = project.cues.filter { $0.track == track && $0.start > frame }.map(\.start).min() ?? Int.max
        let nextLoop = project.loops.filter { $0.frame > frame }.map(\.frame).min() ?? Int.max
        let end = min(frame + project.framesPerSecond * 3, nextCue, nextLoop)
        var cue = Cue(roleID: role, start: frame, end: end, text: text)
        cue.track = track; cue.signs = cue.anchors; cue.signs?[0].kind = kind; cue.pendingEnd = true
        var next = project; next.cues.append(cue); try next.validate(); project = next
        return cue
    }
    /// Half-open intervals allow touching boundaries and crossing loops.
    /// Checking here also protects both editors if the project changes while a
    /// role chooser is open. No existing phrase is shifted or shortened.
    public static func validatePaste(_ source: Cue, in project: Project, frame: Int, track: Int) throws {
        guard (0..<4).contains(track), frame >= max(0, project.mediaStartFrame),
              source.start >= 0, source.end > source.start else { throw ProjectError.invalid("Piste, position ou durée de collage invalide.") }
        guard source.anchors.allSatisfy({ $0.frame >= source.start && $0.frame <= source.end }) else {
            throw ProjectError.invalid("Les signes de la phrase à coller sont invalides.")
        }
        let duration = source.end - source.start
        let (end, overflow) = frame.addingReportingOverflow(duration)
        guard !overflow else { throw ProjectError.invalid("Position de collage trop éloignée.") }
        let occupied = project.cues.filter { $0.track == track }
        if occupied.contains(where: { $0.start <= frame && $0.end > frame }) {
            throw ProjectError.invalid("Impossible de coller : une phrase occupe déjà cette position sur la piste \(track + 1).")
        }
        if let next = occupied.filter({ $0.start >= frame }).map(\.start).min(), next < end {
            let available = Timecode.format(next - frame, fps: project.framesPerSecond)
            let needed = Timecode.format(duration, fps: project.framesPerSecond)
            throw ProjectError.invalid("Place insuffisante sur la piste \(track + 1) : \(available) disponible, \(needed) nécessaire.")
        }
    }
    public static func paste(_ source: Cue, into project: inout Project, frame: Int, track: Int,
                             roleID: UUID?) throws -> Cue {
        try validatePaste(source, in: project, frame: frame, track: track)
        if let roleID, !project.roles.contains(where: { $0.id == roleID }) { throw ProjectError.invalid("Le rôle choisi n'existe plus.") }
        var cue = source
        let delta = frame - cue.start
        cue.id = UUID(); cue.sourceIndex = nil; cue.track = track; cue.roleID = roleID
        cue.start += delta; cue.end += delta
        var signs = source.anchors
        for index in signs.indices { signs[index].id = UUID(); signs[index].sourceIndex = nil; signs[index].frame += delta }
        cue.signs = signs
        var next = project; next.cues.append(cue); try next.validate(); project = next
        return cue
    }
    public static func finalizePhrase(in project: inout Project, id: UUID, frame: Int, kind: String = "out_open") throws {
        guard let index = project.cues.firstIndex(where: { $0.id == id }) else { return }
        var cue = project.cues[index]
        guard kind.hasPrefix("out_") else { throw ProjectError.invalid("Signe de sortie attendu.") }
        guard frame > cue.start else { throw ProjectError.invalid("La fin doit suivre le début de la phrase.") }
        guard !project.cues.contains(where: { $0.id != id && $0.track == cue.track && $0.start < frame && $0.end > cue.start }) else {
            throw ProjectError.invalid("La phrase chevauche une autre phrase.")
        }
        var signs = cue.anchors
        guard signs.dropLast().allSatisfy({ $0.frame <= frame }) else { throw ProjectError.invalid("La fin précède un signe de la phrase.") }
        signs[signs.count - 1].frame = frame; signs[signs.count - 1].kind = kind
        cue.end = frame; cue.signs = signs; cue.pendingEnd = nil
        var next = project; next.cues[index] = cue; try next.validate(); project = next
    }
    public static func movePhrase(in project: inout Project, id: UUID, track: Int) throws {
        guard (0..<4).contains(track) else { throw ProjectError.invalid("Piste invalide.") }
        guard let index = project.cues.firstIndex(where: { $0.id == id }) else { return }
        let cue = project.cues[index]
        guard !project.cues.contains(where: { $0.id != id && $0.track == track && $0.start < cue.end && $0.end > cue.start }) else {
            throw ProjectError.invalid("Une phrase occupe déjà la piste à cet endroit.")
        }
        project.cues[index].track = track
    }
    public static func deletePhrase(in project: inout Project, id: UUID?) {
        project.cues.removeAll { $0.id == id }
    }
    public static func addMarker(in project: inout Project, frame: Int, loop: Bool) {
        guard frame >= project.mediaStartFrame else { return }
        var markers = loop ? project.loops : project.shots
        guard !markers.contains(where: { $0.frame == frame }) else { return }
        markers.append(Marker(frame: frame, label: "")); markers.sort { $0.frame < $1.frame }
        for index in markers.indices { markers[index].label = String(index + 1) }
        if loop { project.loops = markers } else { project.shots = markers }
    }
    public static func mergeRoles(_ candidates: [Role], into project: inout Project) {
        for candidate in candidates where !project.roles.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame
        }) {
            var role = candidate; role.id = UUID(); role.sourceID = nil
            project.roles.append(role)
        }
    }
    public static func detachAllSigns(in cue: inout Cue) {
        var signs = cue.anchors
        for index in signs.indices {
            signs[index].textOffset = Int((Double(signs[index].frame - cue.start) /
                Double(max(1, cue.end - cue.start)) * Double(cue.text.unicodeScalars.count)).rounded())
        }
        cue.signs = signs
    }
}
