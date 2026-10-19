import SwiftUI
import AppKit
import CappellaCore

@MainActor
struct TimelineScroller: NSViewRepresentable {
    let project: Project
    let frame: Int
    let mediaDuration: Double
    let viewportWidth: Double
    let pixelsPerSecond: Double
    let dark: Bool
    var onSeek: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Scroller {
        let control = Scroller(frame: NSRect(x: 0, y: 0, width: 300, height: 16))
        control.controlSize = .small; control.scrollerStyle = .legacy
        control.isContinuous = true
        control.target = context.coordinator
        control.action = #selector(Coordinator.scroll(_:))
        control.trackingChanged = { [weak coordinator = context.coordinator] tracking in coordinator?.tracking = tracking }
        control.setAccessibilityLabel("Position dans la bande rythmo")
        return control
    }
    func updateNSView(_ control: Scroller, context: Context) {
        let coordinator = context.coordinator
        if coordinator.project != project {
            coordinator.project = project
            coordinator.contentEnd = TimelineScrollRange.contentEnd(in: project)
        }
        let range = TimelineScrollRange(startFrame: project.mediaStartFrame, endFrame: coordinator.contentEnd,
            framesPerSecond: project.framesPerSecond, mediaDuration: mediaDuration,
            viewportWidth: viewportWidth, pixelsPerSecond: pixelsPerSecond)
        coordinator.range = range; coordinator.frame = frame; coordinator.onSeek = onSeek
        control.isEnabled = range.isScrollable
        if coordinator.dark != dark {
            control.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            control.knobStyle = dark ? .light : .dark
            coordinator.dark = dark
        }
        if !coordinator.tracking {
            control.knobProportion = CGFloat(range.knobProportion)
            control.doubleValue = range.fraction(at: frame)
        }
    }
    final class Scroller: NSScroller {
        var trackingChanged: ((Bool) -> Void)?
        override func mouseDown(with event: NSEvent) {
            trackingChanged?(true)
            defer { trackingChanged?(false) }
            super.mouseDown(with: event)
        }
    }
    @MainActor final class Coordinator: NSObject {
        var project: Project?
        var contentEnd = 0
        var range = TimelineScrollRange()
        var frame = 0
        var dark: Bool?
        var tracking = false
        var onSeek: ((Int) -> Void)?

        @objc func scroll(_ control: NSScroller) {
            let target: Double
            switch control.hitPart {
            case .decrementLine: target = Double(frame) - 1
            case .incrementLine: target = Double(frame) + 1
            case .decrementPage: target = Double(frame) - range.viewport
            case .incrementPage: target = Double(frame) + range.viewport
            case .knob, .knobSlot: target = Double(range.frame(at: control.doubleValue))
            default: return
            }
            frame = Int(range.clamped(target).rounded())
            onSeek?(frame)
        }
    }
}