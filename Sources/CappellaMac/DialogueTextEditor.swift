import SwiftUI
import AppKit

/// Native input on the band: keep selection/IME/undo in NSTextView, and update
/// the model only for actual edits, never by rewriting the string every frame.
struct DialogueTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var caret: Int
    var fontName = "Apple Chancery"
    var fontSize = 28.0
    var menuProvider: (() -> NSMenu?)? = nil

    /// Measure the same font used by NSTextView, including space for its caret.
    /// The band editor grows with the text, independently of cue duration.
    static func fittingWidth(_ text: String, fontName: String = "Apple Chancery", fontSize: Double = 28) -> CGFloat {
        let font = NSFont(name: fontName, size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize))
        let lines = text.components(separatedBy: .newlines)
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(8, ceil(width) + 8)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder; scroll.drawsBackground = true; scroll.backgroundColor = .black
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        let view = FocusedTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        view.menuProvider = menuProvider
        view.isEditable = true; view.isSelectable = true; view.isRichText = false; view.allowsUndo = true
        view.font = NSFont(name: fontName, size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize))
        view.backgroundColor = .black; view.textColor = .white; view.insertionPointColor = .white
        view.textContainerInset = NSSize(width: 2, height: 0)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isVerticallyResizable = false; view.isHorizontallyResizable = true
        view.autoresizingMask = []
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.lineFragmentPadding = 0
        view.minSize = NSSize(width: 8, height: CGFloat(fontSize) + 4); view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.string = text
        view.sizeToFit()
        view.setSelectedRange(NSRange(location: Self.utf16Offset(caret, in: text), length: 0))
        view.delegate = context.coordinator; scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scroll.documentView as? FocusedTextView)?.menuProvider = menuProvider
        guard let view = scroll.documentView as? FocusedTextView, !view.hasMarkedText() else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.string != text { view.string = text }
        let target = Self.utf16Offset(caret, in: view.string)
        if view.selectedRange().length == 0, view.selectedRange().location != target {
            view.setSelectedRange(NSRange(location: target, length: 0)); view.scrollRangeToVisible(view.selectedRange())
        }
        let font = NSFont(name: fontName, size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize))
        if view.font != font { view.font = font }
        view.sizeToFit()
        view.scrollRangeToVisible(view.selectedRange())
        view.requestInitialFocus()
    }
    private static func utf16Offset(_ offset: Int, in value: String) -> Int {
        let scalars = value.unicodeScalars
        let index = scalars.index(scalars.startIndex, offsetBy: min(max(0, offset), scalars.count))
        return value[..<index].utf16.count
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DialogueTextEditor
        var updating = false
        init(_ parent: DialogueTextEditor) { self.parent = parent }
        private func updateCaret(_ view: NSTextView) {
            let index = String.Index(utf16Offset: min(view.selectedRange().location, view.string.utf16.count), in: view.string)
            parent.caret = view.string[..<index].unicodeScalars.count
        }
        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            view.sizeToFit()
            updateCaret(view); parent.text = view.string
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            updateCaret(view)
        }
    }
    final class FocusedTextView: NSTextView {
        var menuProvider: (() -> NSMenu?)?
        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() ?? super.menu(for: event) }
        private var pendingFocus = true
        private var awaitingSheetEnd = false
        private var focusScheduled = false
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
            guard let window else { return }
            pendingFocus = true
            awaitingSheetEnd = window.attachedSheet != nil
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.requestInitialFocus()
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Cocoa may have temporarily accepted this responder while the
                // sheet was open, then restored the hosting view on dismissal.
                if self.awaitingSheetEnd { self.pendingFocus = true; self.awaitingSheetEnd = false }
                self.requestInitialFocus()
            })
            requestInitialFocus()
        }
        func requestInitialFocus() {
            guard pendingFocus, !focusScheduled, let window else { return }
            if window.attachedSheet != nil { awaitingSheetEnd = true; return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusScheduled = false
                guard self.pendingFocus, let window = self.window else { return }
                if window.attachedSheet != nil { self.awaitingSheetEnd = true; return }
                guard NSApp.modalWindow == nil, self.bounds.width > 0, self.bounds.height > 0 else { return }
                // A responder can be assigned before activation. Keep the
                // request pending until the window actually receives the keys.
                if window.makeFirstResponder(self), window.isKeyWindow {
                    self.pendingFocus = false; self.awaitingSheetEnd = false
                }
            }
        }
        override func layout() { super.layout(); requestInitialFocus() }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
