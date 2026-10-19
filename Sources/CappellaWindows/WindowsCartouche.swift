import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func makeClockPanel() -> Border {
        clockPanel.padding = Thickness(left: 7, top: 5, right: 7, bottom: 5)
        clockPanel.borderBrush = ink(0x70777C)
        clockPanel.borderThickness = Thickness(left: 0, top: 0.5, right: 0, bottom: 0)
        let content = Grid()
        let headerRow = RowDefinition(); headerRow.height = GridLength(value: 0, gridUnitType: .auto)
        let detailsRow = RowDefinition(); detailsRow.height = GridLength(value: 1, gridUnitType: .star)
        let footerRow = RowDefinition(); footerRow.height = GridLength(value: 18, gridUnitType: .pixel)
        content.rowDefinitions.append(headerRow); content.rowDefinitions.append(detailsRow); content.rowDefinitions.append(footerRow)
        let caption = label("timecode", size: 10, color: ink(0xFFFFFF))
        caption.width = 52; caption.verticalAlignment = .bottom
        caption.margin = Thickness(left: 0, top: 0, right: 0, bottom: 7)
        timecode.fontFamily = FontFamily("Segoe UI")
        timecode.fontWeight = FontWeights.light
        let header = row([caption, timecode], spacing: 9)
        header.tapped.addHandler { [weak self] _, _ in
            Task { @MainActor [weak self] in await self?.goTimecode() }
        }
        content.children.append(header)
        loopLabel.verticalAlignment = .top
        loopLabel.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
        try? Grid.setRow(loopLabel, 1); content.children.append(loopLabel)
        let footer = Grid()
        for unit in [GridUnitType.star, .auto, .star] {
            let column = ColumnDefinition(); column.width = GridLength(value: 1, gridUnitType: unit)
            footer.columnDefinitions.append(column)
        }
        loopRange.verticalAlignment = .center; loopRange.textTrimming = .characterEllipsis
        footer.children.append(loopRange)
        for control in [vo, vi] {
            control.fontSize = 10
            control.minWidth = 0; control.minHeight = 0; control.width = 17; control.height = 18
            control.padding = Thickness(); control.borderThickness = Thickness()
            control.background = brush(0, 0, 0, alpha: 0)
            control.borderBrush = brush(0, 0, 0, alpha: 0)
            control.isTabStop = false
            for key in ["ButtonBackgroundPointerOver", "ButtonBackgroundPressed", "ButtonBorderBrushPointerOver", "ButtonBorderBrushPressed"] {
                _ = control.resources.insert(key, brush(0, 0, 0, alpha: 0))
            }
        }
        let switches = row([vo, vi], spacing: 3)
        try? Grid.setColumn(switches, 1); footer.children.append(switches)
        try? Grid.setRow(footer, 2); content.children.append(footer)
        clockPanel.child = content
        refreshClockStyle()
        return clockPanel
    }
    func refreshClockStyle() {
        clockPanel.background = ink(dark ? 0x171717 : 0x232B31)
        timecode.foreground = ink(0xFFFFFF); loopLabel.foreground = ink(0xDDDDDD)
        loopRange.foreground = ink(dark ? 0xB8C1C7 : 0x6E8796)
        let muted = dark ? UInt32(0x919DA5) : UInt32(0x647785)
        vo.foreground = ink(media.hasMedia && !media.usingVI ? 0xFFFFFF : muted)
        vi.foreground = ink(media.hasMedia && media.usingVI ? 0xFFFFFF : muted)
        vo.opacity = 1; vi.opacity = 1
    }
    func refreshClock() {
        refreshTimelineScrollbar()
        let cadenceChanged = displayedFPS != fps
        if displayedFrame != self.document.frame || displayedFPS != fps {
            timecode.text = Timecode.format(self.document.frame, fps: fps)
            displayedFrame = self.document.frame; displayedFPS = fps
        }
        if clockProjectRevision != self.document.revision {
            clockLastCueEnd = self.document.project.cues.map(\.end).max() ?? 0
            clockProjectRevision = self.document.revision
        }
        let loop = self.document.currentLoop
        let loopEnd: Int?
        if let loop {
            let next = self.document.nextLoop(after: loop.frame)?.frame
            let lastCue = max(clockLastCueEnd, loop.frame)
            let mediaEnd = self.document.project.mediaStartFrame + Int(media.duration * Double(fps))
            loopEnd = next ?? max(lastCue, mediaEnd)
        } else { loopEnd = nil }
        if displayedLoop != loop || displayedLoopEnd != loopEnd || cadenceChanged {
            if let loop, let end = loopEnd {
                let seconds = max(0, end - loop.frame) / max(1, fps)
                loopLabel.text = "boucle  \(loop.label)       durée  \(seconds / 60) min \(seconds % 60) s"
                loopRange.text = Timecode.format(loop.frame, fps: fps) + " → " + Timecode.format(end, fps: fps)
                loopLabel.visibility = .visible; loopRange.visibility = .visible
            } else {
                loopLabel.text = ""; loopRange.text = ""
                loopLabel.visibility = .collapsed; loopRange.visibility = .collapsed
            }
            displayedLoop = loop; displayedLoopEnd = loopEnd
        }
        if displayedVI != media.usingVI || displayedClockMedia != media.hasMedia {
            refreshClockStyle()
            displayedVI = media.usingVI; displayedClockMedia = media.hasMedia
            refreshMenuChecks()
        }
    }
}
