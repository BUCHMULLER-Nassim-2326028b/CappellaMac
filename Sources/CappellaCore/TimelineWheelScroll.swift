/// One wheel notch advances one frame, independently of zoom or frame rate.
public struct TimelineWheelScroll {
    private var remainder = 0.0
    private var lastFrame: Int?

    public init() {}

    public mutating func target(currentFrame: Int, stepDelta: Double,
                                range: TimelineScrollRange) -> Int? {
        guard stepDelta.isFinite, stepDelta != 0 else { return nil }
        if lastFrame != currentFrame || remainder * stepDelta < 0 { remainder = 0 }
        remainder += stepDelta
        let steps = remainder.rounded(.towardZero)
        remainder -= steps
        let target = Int(range.clamped(Double(currentFrame) + steps).rounded())
        if target == currentFrame && steps != 0 { remainder = 0 }
        lastFrame = target
        return target == currentFrame ? nil : target
    }
}
