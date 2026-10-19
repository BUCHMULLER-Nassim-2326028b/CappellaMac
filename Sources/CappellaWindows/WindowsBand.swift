import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

struct WindowsBandState: Equatable {
    var revision: UInt64
    var track: Int
    var selection: UUID?
    var sign: UUID?
    var editing: Bool
    var preferences: ApplicationPreferences
}

struct WindowsRulerState: Equatable {
    var width: Double
    var height: Double
    var scale: Double
    var fps: Int
    var dark: Bool
    var visible: Bool
}

extension WindowsEditor {
    func renderBand(reuse: Bool = false) {
        let width = bandContainer.actualWidth, height = bandContainer.actualHeight
        guard width > 0, height > 0 else { return }
        let position = reuse ? (playbackFrame ?? Double(self.document.frame)) : Double(self.document.frame)
        let state = WindowsBandState(revision: self.document.revision, track: self.document.track,
            selection: self.document.selection, sign: self.document.signSelection,
            editing: self.document.editing, preferences: self.document.preferences)
        let invalid = bandState != state || width != bandCacheWidth || height != bandCacheHeight
        let lane = height / 4, center = width / 2
        if invalid {
            bandState = state; bandCacheWidth = width; bandCacheHeight = height
            bandOriginFrame = Int(position)
            band.children.clear(); bandCueViews.removeAll(); bandMarkerViews.removeAll()
            bandBackdrop.children.clear(); bandOverlay.children.clear()
            bandMotion.invalidate(); lastBandPopulation = -.infinity
            let clip = RectangleGeometry()
            clip.rect = WindowsFoundation.Rect(x: 0, y: 0, width: Float(width), height: Float(height))
            bandContainer.clip = clip
            for track in 0..<4 {
                let selected = self.document.track == track
                rectangle(on: bandBackdrop, x: 0, y: Double(track) * lane, width: width, height: lane,
                    color: ink(dark ? (selected ? 0x555555 : 0x303030) : (selected ? 0xFAFAFA : 0xA8A8A8)))
                if self.document.preferences.showGrid {
                    rectangle(on: bandBackdrop, x: 0, y: Double(track) * lane, width: width, height: 0.5,
                        color: ink(dark ? 0x777777 : 0x555555))
                }
            }
            rectangle(on: bandOverlay, x: center - 1, y: 0, width: 2, height: height, color: ink(0xC40000))
        } else if abs((Double(bandOriginFrame) - position) * scale) > 65_536 {
            // Rebase coordinates without rebuilding text; bound floating-point error
            // during long sessions while retaining the same visible objects.
            let nextOrigin = Int(position), delta = Double(bandOriginFrame - nextOrigin) * scale
            for view in Array(bandCueViews.values) + Array(bandMarkerViews.values) {
                if let left = try? Canvas.getLeft(view) { try? Canvas.setLeft(view, left + delta) }
            }
            bandOriginFrame = nextOrigin; bandMotion.invalidate()
        }
        let speed = timelineSpeed
        bandMotion.update(band, offset: (Double(bandOriginFrame) - position) * scale,
            speed: speed, fallback: bandTranslation)
        updateRuler(width: width, height: height, position: position)
        let now = ProcessInfo.processInfo.systemUptime
        guard invalid || !reuse || now - lastBandPopulation >= 0.1 else { return }
        lastBandPopulation = now
        // Prefetch outside the viewport. Only entering/leaving cues change the tree;
        // nothing already visible is periodically destroyed and measured again.
        let from = position - width * 1.5 / scale, to = position + width * 1.5 / scale
        let cues = self.document.project.cues.filter {
            (0..<4).contains($0.track) && Double($0.end) >= from && Double($0.start) <= to
        }
        let cueIDs = Set(cues.map(\.id))
        for id in Array(bandCueViews.keys) where !cueIDs.contains(id) {
            if let view = bandCueViews.removeValue(forKey: id) { detachBandView(view) }
        }
        for cue in cues where bandCueViews[cue.id] == nil {
            let view = makeBandCue(cue, lane: lane)
            place(view, on: band, x: center + Double(cue.start - bandOriginFrame) * scale, y: 0,
                width: max(1, Double(cue.end - cue.start) * scale), height: height)
            bandCueViews[cue.id] = view
        }
        var markerIDs = Set<UUID>()
        if self.document.preferences.showDetection {
            let groups: [([Marker], Bool)] = [(self.document.project.shots, false), (self.document.project.loops, true)]
            for (markers, isLoop) in groups {
                for marker in markers where Double(marker.frame) >= from && Double(marker.frame) <= to {
                    markerIDs.insert(marker.id)
                    guard bandMarkerViews[marker.id] == nil else { continue }
                    let view = Canvas()
                    rectangle(on: view, x: isLoop ? -2 : -3, y: 0, width: isLoop ? 4 : 6, height: height,
                        color: ink(isLoop ? 0x0069C7 : 0x666666))
                    if isLoop {
                        let badge = Border(); badge.background = ink(0x0069C7)
                        badge.child = label(marker.label, size: 13, color: ink(0xFFFFFF))
                        place(badge, on: view, x: -8, y: height - 21, width: 22, height: 21)
                    }
                    try? Canvas.setZIndex(view, 1)
                    place(view, on: band, x: center + Double(marker.frame - bandOriginFrame) * scale, y: 0,
                        width: 1, height: height)
                    bandMarkerViews[marker.id] = view
                }
            }
        }
        for id in Array(bandMarkerViews.keys) where !markerIDs.contains(id) {
            if let view = bandMarkerViews.removeValue(forKey: id) { detachBandView(view) }
        }
    }
    var timelineSpeed: Double {
        guard !self.document.editing, !dialogShowing, media.rate != 0 else { return 0 }
        if media.hasMedia && media.rate > 0 && !media.isAdvancing { return 0 }
        return -scale * Double(fps) * media.rate
    }
    func detachBandView(_ view: Canvas) {
        if let index = band.children.index(of: view) { band.children.removeAt(UInt32(index)) }
    }
    func makeBandCue(_ cue: Cue, lane: Double) -> Canvas {
        let view = Canvas(), y = Double(cue.track) * lane
        if self.document.preferences.showDetection {
            let role = self.document.project.roles.first { $0.id == cue.roleID }
            let name = label(role?.name ?? "Sans rôle", size: 10, color: ink(0xFFFFFF))
            let badge = Border(); badge.background = ink(0); badge.child = name
            try? name.measure(uiSize(width: 500, height: 20))
            place(badge, on: view, x: -Double(name.desiredSize.width) - 8, y: y,
                width: Double(name.desiredSize.width) + 6, height: 15)
        }
        if !self.document.editing || self.document.selection != cue.id {
            let color = readingColor(cue.roleID), font = FontFamily(fontFamily)
            for segment in Timeline.segments(cue) {
                let textWidth = Double(segment.end - segment.start) * scale
                guard textWidth > 0 else { continue }
                let text = label(segment.text, size: self.document.preferences.fontSize, color: color)
                text.fontFamily = font; text.fontStyle = .italic
                try? text.measure(uiSize(width: 100_000, height: lane))
                let naturalWidth = Double(text.desiredSize.width), naturalHeight = Double(text.desiredSize.height)
                guard naturalWidth > 0 else { continue }
                let transform = CompositeTransform(); transform.scaleX = textWidth / naturalWidth
                text.renderTransform = transform; text.protectedCursor = bandTextCursor
                place(text, on: view, x: Double(segment.start - cue.start) * scale,
                    y: y + max(0, (lane - naturalHeight) / 2), width: naturalWidth, height: naturalHeight)
            }
        }
        if self.document.preferences.showGrid {
            for sign in cue.anchors {
                let x = Double(sign.frame - cue.start) * scale
                let color = sign.kind.hasPrefix("in_") ? ink(0x00D800) : sign.kind.hasPrefix("out_") ? ink(0xED1515) : ink(dark ? 0xFFFFFF : 0x111111)
                let mark = label(sign.kind.hasPrefix("in_") || sign.kind.hasPrefix("out_") ? "\u{2B06}" : "\u{2502}", size: 18, color: color)
                place(mark, on: view, x: x - 6, y: y + lane - 22, width: 15, height: 22)
                if sign.id == self.document.signSelection {
                    let outline = Border(); outline.borderBrush = ink(0x328BFF)
                    outline.borderThickness = Thickness(left: 1, top: 1, right: 1, bottom: 1)
                    place(outline, on: view, x: x - 7, y: y + lane - 22, width: 15, height: 22)
                }
            }
        }
        return view
    }
    func updateRuler(width: Double, height: Double, position: Double) {
        // Tick marks repeat every second. Slide one persistent geometry modulo
        // that period instead of rebuilding it when the dialogue cache recenters.
        let period = Double(max(1, fps))
        rulerMotion.update(bandRuler, offset: -position.truncatingRemainder(dividingBy: period) * scale,
            speed: timelineSpeed, fallback: rulerTranslation)
        let state = WindowsRulerState(width: width, height: height, scale: scale,
            fps: fps, dark: dark, visible: self.document.preferences.showGrid)
        guard state != rulerState else { return }
        rulerState = state; bandRuler.children.clear()
        guard state.visible else { return }
        let lane = height / 4, margin = 2 * period * scale + 8
        let halfFrames = Int((width / 2 + margin) / scale) + 1
        let geometry = PathGeometry()
        // Use stable subdivisions so repeating the one-second pattern is seamless.
        let minimumStep = max(1, Int(4 / scale))
        let step = (1...max(1, fps)).first { $0 >= minimumStep && fps % $0 == 0 } ?? 1
        for frame in stride(from: -halfFrames - halfFrames % step, through: halfFrames, by: step) {
            let x = Float(width / 2 + Double(frame) * scale + margin)
            for track in 0..<4 {
                let y = Float(Double(track) * lane)
                let figure = PathFigure(); figure.isFilled = false
                figure.startPoint = Point(x: x, y: y)
                let segment = LineSegment(); segment.point = Point(x: x, y: y + (frame % fps == 0 ? 7 : 2))
                figure.segments.append(segment); geometry.figures.append(figure)
            }
        }
        let ruler = WinUI.Path(); ruler.data = geometry
        ruler.stroke = ink(dark ? 0x999999 : 0x666666); ruler.strokeThickness = 0.5
        ruler.isHitTestVisible = false
        place(ruler, on: bandRuler, x: -margin, y: 0, width: width + 2 * margin, height: height)
    }
    var fontFamily: String {
        ["Apple Chancery", "Snell Roundhand", "Segoe Script"].contains(self.document.preferences.fontName) ? "Monotype Corsiva" : self.document.preferences.fontName
    }
    func readingColor(_ roleID: UUID?) -> SolidColorBrush {
        let role = self.document.project.roles.first { $0.id == roleID }
        let palette: [UInt32] = [0x0070C0, 0xD52020, 0x008020, 0x8030A0, 0xBB6500, 0x008090]
        let stored = role?.hexColor.flatMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) }
        let value = stored ?? role.map { palette[abs($0.color) % palette.count] } ?? 0
        if !dark { return ink(value) }
        if value == 0 { return ink(0xFFFFFF) }
        return brush(Double((value >> 16) & 255) / 255 * 0.55 + 0.45, Double((value >> 8) & 255) / 255 * 0.55 + 0.45, Double(value & 255) / 255 * 0.55 + 0.45)
    }
    func hit(_ point: Point) -> (Cue?, SyncSign?, Int, Int) {
        let lane = max(1, bandContainer.actualHeight / 4)
        let track = min(3, max(0, Int(Double(point.y) / lane)))
        let target = self.document.frame + Int(((Double(point.x) - bandContainer.actualWidth / 2) / scale).rounded())
        let cue = self.document.project.cues.last { $0.track == track && $0.start <= target && $0.end >= target }
        let sign = cue?.anchors.first { abs(Double($0.frame - target) * scale) < 7 && Double(point.y) >= Double(track + 1) * lane - 23 }
        return (cue, sign, track, target)
    }
    func pointerPressed(_ args: PointerRoutedEventArgs?) {
        guard let args, let point = try? args.getCurrentPoint(bandContainer), point.properties.isLeftButtonPressed else { return }
        let (cue, sign, _, _) = hit(point.position)
        dragMoved = false; pointerWasLeft = true
        if let cue, let sign { dragSign = (cue.id, sign.id, sign.frame, Double(point.position.x)) }
    }
    func pointerMoved(_ args: PointerRoutedEventArgs?) {
        guard let args, let point = try? args.getCurrentPoint(bandContainer) else { return }
        if let (cueID, signID, initialFrame, x) = dragSign, point.properties.isLeftButtonPressed {
            let delta = Double(point.position.x) - x
            if abs(delta) > 3 {
                dragMoved = true; self.document.selection = cueID; self.document.signSelection = signID
                perform { try self.document.mutateCue { Timeline.moveSign(in: &$0, id: signID, to: max(0, initialFrame + Int((delta / scale).rounded()))) } }
            }
        }
    }
    func pointerReleased(_ args: PointerRoutedEventArgs?) {
        defer { dragSign = nil; dragMoved = false; pointerWasLeft = false }
        guard pointerWasLeft, !dragMoved, let args, let point = try? args.getCurrentPoint(bandContainer), !point.properties.isRightButtonPressed else { return }
        let (cue, _, track, target) = hit(point.position)
        media.stop()
        if let cue { self.document.beginEditing(cue, at: target); updateTextEditor(focus: true) }
        else { self.document.selectTrack(track); updateTextEditor() }
    }
    func updateTextEditor(focus: Bool = false) {
        guard self.document.editing, let cue = self.document.selectedCue else {
            if textEditor != nil { editorLayer.children.clear(); textEditor = nil; textEditorCue = nil }
            return
        }
        if textEditorCue != cue.id {
            editorLayer.children.clear()
            let input = TextBox(); input.fontFamily = FontFamily(fontFamily); input.fontSize = self.document.preferences.fontSize
            input.fontStyle = .italic
            input.background = ink(0); input.foreground = ink(0xFFFFFF); input.textWrapping = .noWrap
            input.borderThickness = Thickness(); input.padding = Thickness(left: 2, top: 0, right: 2, bottom: 0)
            input.acceptsReturn = false; input.text = cue.text
            input.textChanged.addHandler { [weak self, weak input] _, _ in
                guard let self, let input, !changingText, textEditor === input,
                      textEditorCue == self.document.selection, self.document.editing else { return }
                let count = min(Int(input.selectionStart), input.text.utf16.count)
                let index = String.Index(utf16Offset: count, in: input.text)
                perform { try self.document.setText(input.text, caret: input.text[..<index].unicodeScalars.count) }
            }
            input.loaded.addHandler { [weak self, weak input] _, _ in
                guard let self, let input, textEditor === input, self.document.editing, !dialogShowing else { return }
                _ = try? input.focus(.programmatic)
            }
            textEditor = input; textEditorCue = cue.id; editorLayer.children.append(input)
            let scalars = cue.text.unicodeScalars
            let index = scalars.index(scalars.startIndex, offsetBy: min(self.document.caret, scalars.count))
            input.selectionStart = Int32(cue.text[..<index].utf16.count)
        }
        guard let input = textEditor else { return }
        changingText = true
        if input.text != cue.text { input.text = cue.text }
        let measured = editorMeasurement
        measured.text = cue.text + " "; measured.fontSize = self.document.preferences.fontSize
        measured.fontFamily = FontFamily(fontFamily); measured.fontStyle = .italic
        try? measured.measure(uiSize(width: 100_000, height: bandContainer.actualHeight / 4))
        let left = max(0, bandContainer.actualWidth / 2 + Double(cue.start - self.document.frame) * scale)
        try? Canvas.setLeft(input, left); try? Canvas.setTop(input, Double(cue.track) * bandContainer.actualHeight / 4)
        input.width = min(max(12, Double(measured.desiredSize.width) + 12), max(12, bandContainer.actualWidth - left))
        input.height = bandContainer.actualHeight / 4
        changingText = false
        if focus { _ = try? input.focus(.programmatic) }
    }
}
