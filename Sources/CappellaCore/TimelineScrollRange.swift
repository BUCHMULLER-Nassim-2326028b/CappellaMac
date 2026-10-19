import Foundation

/// Shared frame range and viewport size for native horizontal timeline scrollers.
public struct TimelineScrollRange: Equatable {
    public let minimum: Double
    public let maximum: Double
    public let viewport: Double
    public var isScrollable: Bool { maximum > minimum }
    public var knobProportion: Double { min(1, viewport / (maximum - minimum + viewport)) }

    public init(startFrame: Int = 0, endFrame: Int = 0, framesPerSecond: Int = 25,
                mediaDuration: Double = 0, viewportWidth: Double = 0, pixelsPerSecond: Double = 120) {
        let fps = Double(max(1, framesPerSecond))
        let duration = mediaDuration.isFinite ? max(0, mediaDuration) : 0
        minimum = Double(startFrame)
        maximum = max(minimum, max(Double(endFrame), minimum + duration * fps))
        viewport = max(1, max(0, viewportWidth) * fps / max(1, pixelsPerSecond))
    }
    public func clamped(_ frame: Double) -> Double {
        frame.isFinite ? min(maximum, max(minimum, frame)) : minimum
    }
    public func fraction(at frame: Int) -> Double {
        isScrollable ? (clamped(Double(frame)) - minimum) / (maximum - minimum) : 0
    }
    public func frame(at fraction: Double) -> Int {
        Int(clamped(minimum + min(1, max(0, fraction)) * (maximum - minimum)).rounded())
    }
    public static func contentEnd(in project: Project) -> Int {
        var end = project.mediaStartFrame
        for cue in project.cues { end = max(end, cue.end) }
        for marker in project.loops { end = max(end, marker.frame) }
        for marker in project.shots { end = max(end, marker.frame) }
        for marker in project.positions ?? [] { end = max(end, marker.frame) }
        return end
    }
}