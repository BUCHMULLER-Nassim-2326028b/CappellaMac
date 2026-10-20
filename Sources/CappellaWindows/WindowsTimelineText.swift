import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func scalarOffset(in text: String, utf16: Int) -> Int {
        var units = 0, count = 0
        for scalar in text.unicodeScalars {
            let length = scalar.value > 0xFFFF ? 2 : 1
            if units + length > max(0, utf16) { break }
            units += length; count += 1
        }
        return count
    }
    func utf16Offset(in text: String, scalar: Int) -> Int {
        let values = text.unicodeScalars
        let index = values.index(values.startIndex, offsetBy: min(max(0, scalar), values.count))
        return text[..<index].utf16.count
    }
    func measureTimelineText(_ text: String) -> Double {
        editorMeasurement.text = text
        editorMeasurement.fontFamily = FontFamily(fontFamily)
        editorMeasurement.fontStyle = .italic
        editorMeasurement.fontSize = self.document.preferences.fontSize
        try? editorMeasurement.measure(uiSize(width: 100_000, height: 1000))
        return Double(editorMeasurement.desiredSize.width)
    }
    func timelineCueEndFrame(_ cue: Cue) -> Double {
        let editing = self.document.editing && self.document.selection == cue.id
        guard cue.pendingEnd == true else { return Double(cue.end) }
        let end = Timeline.segments(cue, editing: editing).map { segment in
            Double(segment.start) + (segment.naturalWidth ? measureTimelineText(segment.text) / scale : Double(segment.end - segment.start))
        }.max() ?? Double(cue.start)
        return max(Double(cue.end), end)
    }
    func timelineCaretX(_ cue: Cue, offset: Int) -> Double {
        let anchors = cue.anchors, values = cue.text.unicodeScalars
        let offset = min(max(0, offset), values.count)
        let center = bandContainer.actualWidth / 2
        if cue.pendingEnd == true {
            let caret = values.index(values.startIndex, offsetBy: offset)
            return center + Double(cue.start) * scale - bandDisplayFrame * scale
                + measureTimelineText(String(values[..<caret]))
        }
        for (left, right) in zip(anchors, anchors.dropFirst()) where right.textOffset > left.textOffset && offset <= right.textOffset {
            let start = values.index(values.startIndex, offsetBy: left.textOffset)
            let end = values.index(values.startIndex, offsetBy: right.textOffset)
            let caret = values.index(values.startIndex, offsetBy: max(left.textOffset, offset))
            let whole = measureTimelineText(String(values[start..<end]))
            let prefix = measureTimelineText(String(values[start..<caret]))
            let ratio = whole > 0 ? prefix / whole : 0
            let frame = Double(left.frame) + Double(right.frame - left.frame) * ratio
            return center + (frame - bandDisplayFrame) * scale
        }
        return center + (Double(offset == 0 ? cue.start : cue.end) - bandDisplayFrame) * scale
    }
    func timelineOffset(_ cue: Cue, atX x: Double) -> Int {
        var low = 0, high = cue.text.unicodeScalars.count
        while low < high {
            let middle = low + (high - low) / 2
            if timelineCaretX(cue, offset: middle) < x { low = middle + 1 } else { high = middle }
        }
        if low > 0, abs(timelineCaretX(cue, offset: low - 1) - x) < abs(timelineCaretX(cue, offset: low) - x) { return low - 1 }
        return low
    }
    func updateTextEditor(focus: Bool = false) {
        guard !isClosed, !changingText else { return }
        guard self.document.editing, let cue = self.document.selectedCue else {
            try? caretTimer.stop()
            if textEditor != nil { editorLayer.children.clear(); textEditor = nil; textEditorCue = nil }
            editorAdornments.children.clear()
            return
        }
        if textEditorCue != cue.id {
            editorLayer.children.clear()
            let input = TextBox()
            // Only the timeline renderer is visible. Retain native text services
            // for Unicode/IME, accents, clipboard and keyboard text selection.
            input.opacity = 0; input.isHitTestVisible = true
            input.fontFamily = FontFamily(fontFamily); input.fontStyle = .italic
            input.fontSize = self.document.preferences.fontSize
            input.background = brush(0, 0, 0, alpha: 0)
            input.borderThickness = Thickness(); input.padding = Thickness()
            input.minWidth = 0; input.minHeight = 0
            input.acceptsReturn = true; input.textWrapping = .noWrap
            input.isSpellCheckEnabled = false; input.isTextPredictionEnabled = false
            input.text = cue.text
            input.textChanged.addHandler { [weak self, weak input] _, _ in
                guard let self, let input, !changingText, textEditor === input,
                      textEditorCue == self.document.selection, self.document.editing else { return }
                let text = input.text
                let caret = scalarOffset(in: text, utf16: Int(input.selectionStart))
                // Publishing refreshes the whole editor synchronously. Never
                // echo the model back into the native control during this edit.
                changingText = true
                perform { try self.document.setText(text, caret: caret) }
                changingText = false
                if let cue = self.document.selectedCue { positionTimelineInput(input, cue: cue) }
                resetTimelineCaret()
            }
            input.selectionChanged.addHandler { [weak self, weak input] _, _ in
                guard let self, let input, textEditor === input, !changingText else { return }
                // WinUI may deliver SelectionChanged before TextChanged.
                // In that case the native text is newer than the document.
                guard let cue = self.document.selectedCue, input.text == cue.text else { return }
                self.document.caret = scalarOffset(in: input.text, utf16: Int(input.selectionStart))
                positionTimelineInput(input, cue: cue); resetTimelineCaret()
            }
            input.loaded.addHandler { [weak self, weak input] _, _ in
                guard let self, let input, textEditor === input, self.document.editing, !dialogShowing else { return }
                _ = try? input.focus(.programmatic); resetTimelineCaret()
            }
            input.gotFocus.addHandler { [weak self] _, _ in self?.resetTimelineCaret() }
            input.lostFocus.addHandler { [weak self] _, _ in self?.renderEditorAdornments() }
            textEditor = input; textEditorCue = cue.id
            editorLayer.children.append(input)
            editorAdornments.isHitTestVisible = false; editorLayer.children.append(editorAdornments)
            changingText = true
            try? input.select(Int32(utf16Offset(in: cue.text, scalar: self.document.caret)), 0)
            changingText = false
        }
        guard let input = textEditor else { return }
        changingText = true
        // While focused, the native input owns the text until TextChanged has
        // published it. Layout/selection refreshes must not discard that text.
        if input.focusState == .unfocused && input.text != cue.text { input.text = cue.text }
        if focus { try? input.select(Int32(utf16Offset(in: cue.text, scalar: self.document.caret)), 0) }
        positionTimelineInput(input, cue: cue)
        changingText = false
        if focus {
            _ = try? input.focus(.programmatic)
            // Pointer-release and dialog-close processing can restore the old
            // focus after this call. Reassert it once those events have finished.
            DispatchQueue.main.async { [weak self, weak input] in
                guard let self, let input, !isClosed, !dialogShowing,
                      self.document.editing, textEditor === input,
                      textEditorCue == self.document.selection else { return }
                _ = try? input.focus(.programmatic); resetTimelineCaret()
            }
        }
        renderEditorAdornments()
    }
    func positionTimelineInput(_ input: TextBox, cue: Cue) {
        let offset = scalarOffset(in: cue.text, utf16: Int(input.selectionStart))
        let lane = max(1, bandContainer.actualHeight / 4)
        // Keep the native input inside the visible timeline even when the
        // stretched text's caret lies outside it. Offscreen controls lose focus.
        let x = min(max(0, bandContainer.actualWidth - 2), max(0, timelineCaretX(cue, offset: offset)))
        try? Canvas.setLeft(input, x)
        try? Canvas.setTop(input, Double(cue.track) * lane)
        input.width = 2; input.height = lane
    }
    func resetTimelineCaret() {
        caretVisible = true
        try? caretTimer.stop(); try? caretTimer.start()
        renderEditorAdornments()
    }
    func renderEditorAdornments() {
        editorAdornments.children.clear()
        guard !isClosed, self.document.editing, !dialogShowing, let cue = self.document.selectedCue,
              let input = textEditor, input.focusState != .unfocused else { return }
        let lane = bandContainer.actualHeight / 4
        let height = min(lane - 4, self.document.preferences.fontSize * 1.1)
        let y = Double(cue.track) * lane + max(0, (lane - height) / 2)
        let a = scalarOffset(in: cue.text, utf16: Int(input.selectionStart))
        let b = scalarOffset(in: cue.text, utf16: Int(input.selectionStart + input.selectionLength))
        let left = timelineCaretX(cue, offset: a), right = timelineCaretX(cue, offset: b)
        if a != b {
            rectangle(on: editorAdornments, x: min(left, right), y: y, width: max(1, abs(right - left)), height: height,
                color: brush(0.15, 0.45, 1, alpha: 0.3))
        } else if caretVisible {
            rectangle(on: editorAdornments, x: left, y: y, width: 1.5, height: height, color: ink(dark ? 0xFFFFFF : 0))
        }
    }
}