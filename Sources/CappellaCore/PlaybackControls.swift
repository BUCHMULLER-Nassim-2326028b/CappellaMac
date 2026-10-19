import Foundation

public struct ShuttleSpeed: Identifiable, Equatable {
    public let rate: Double
    public let title: String
    public var id: Double { rate }
}

public enum PlaybackControls {
    public static let jogSpeed = 0.25
    public static let shuttleSpeeds: [ShuttleSpeed] = [
        -10.0, -3, -1, -0.75, -0.5, -0.25, -0.125,
        0.125, 0.25, 0.5, 0.75, 1, 3, 10
    ].map { rate in
        var magnitude = String(abs(rate))
        if magnitude.hasSuffix(".0") { magnitude.removeLast(2) }
        return ShuttleSpeed(rate: rate, title: (rate < 0 ? "Arrière" : "Avant") + " x" + magnitude)
    }
}

public struct ControlDestination {
    public let frame: Int
    public let cueID: UUID?
    public let track: Int?
    public let signID: UUID?
}

/// All transport navigation uses the same ordering, bounds and role selection.
public enum ControlNavigation {
    public static func destination(in project: Project, kind: String, direction: Int,
                                   from frame: Int, selection: UUID?, mediaDuration: Double) -> ControlDestination? {
        let selectedRole = project.cues.first(where: { $0.id == selection })?.roleID
        let targets: [Int]
        switch kind {
        case "loop": targets = project.loops.map(\.frame)
        case "shot": targets = project.shots.map(\.frame)
        case "phrase": targets = project.cues.map(\.start)
        case "role": targets = project.cues.filter { $0.roleID == selectedRole }.map(\.start)
        case "sign": targets = Timeline.snapFrames(in: project)
        default: return nil
        }
        let lastFrame: Int
        if mediaDuration.isFinite, mediaDuration > 0 {
            lastFrame = project.mediaStartFrame + Timeline.frame(at: mediaDuration, fps: project.framesPerSecond, playing: true)
        } else { lastFrame = Int.max }
        let reachable = targets.filter { $0 >= project.mediaStartFrame && $0 <= lastFrame }
        guard let target = Timeline.adjacentFrame(in: reachable, from: frame, direction: direction) else { return nil }
        let candidates = project.cues.filter { cue in
            if kind == "role", cue.roleID != selectedRole { return false }
            return kind == "sign" ? cue.anchors.contains(where: { $0.frame == target }) : cue.start == target
        }.sorted { left, right in
            left.track == right.track ? left.start < right.start : left.track < right.track
        }
        let cue = candidates.first
        let sign = kind == "sign" ? cue?.anchors.first(where: { $0.frame == target })?.id : nil
        return ControlDestination(frame: target, cueID: cue?.id, track: cue?.track, signID: sign)
    }
}
