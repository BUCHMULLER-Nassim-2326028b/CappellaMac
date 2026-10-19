import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation

extension WindowsEditor {
    func installTimelineScrollbar() {
        timelineScrollbar.orientation = .horizontal
        timelineScrollbar.indicatorMode = .mouseIndicator
        timelineScrollbar.height = 16; timelineScrollbar.minHeight = 0
        timelineScrollbar.isTabStop = false
        try? AutomationProperties.setName(timelineScrollbar, "Position dans la bande rythmo")
        timelineScrollbar.scroll.addHandler { [weak self] _, args in
            guard let self, let args, !isClosed, !updatingTimelineScrollbar else { return }
            media.stop()
            self.document.finishEditing(); updateTextEditor()
            seek(Int(timelineScrollRange().clamped(args.newValue).rounded()))
        }
    }
    func timelineScrollRange() -> TimelineScrollRange {
        if timelineScrollRevision != self.document.revision {
            timelineScrollEnd = TimelineScrollRange.contentEnd(in: self.document.project)
            timelineScrollRevision = self.document.revision
        }
        return TimelineScrollRange(startFrame: self.document.project.mediaStartFrame, endFrame: timelineScrollEnd,
            framesPerSecond: fps, mediaDuration: media.duration,
            viewportWidth: bandContainer.actualWidth, pixelsPerSecond: self.document.preferences.pixelsPerSecond)
    }
    func refreshTimelineScrollbar() {
        let range = timelineScrollRange()
        updatingTimelineScrollbar = true
        defer { updatingTimelineScrollbar = false }
        if timelineScrollRangeCache != range {
            // Coerce bounds in a safe order when the document origin changes.
            if range.minimum < timelineScrollbar.minimum { timelineScrollbar.minimum = range.minimum }
            timelineScrollbar.maximum = range.maximum
            timelineScrollbar.minimum = range.minimum
            timelineScrollbar.viewportSize = range.viewport
            timelineScrollbar.largeChange = range.viewport
            timelineScrollbar.smallChange = 1
            timelineScrollbar.isEnabled = range.isScrollable
            timelineScrollRangeCache = range
        }
        let value = range.clamped(Double(self.document.frame))
        // Do not round the thumb back on every drag event. The playhead uses
        // integral frames, but the native scroll thumb tracks fractional values.
        if abs(timelineScrollbar.value - value) > 0.5 { timelineScrollbar.value = value }
    }
}