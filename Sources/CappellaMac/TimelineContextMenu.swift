import SwiftUI
import AppKit
import CappellaCore

/// Secondary clicks and wheel navigation leave left clicks, text selection and
/// sign drags to their existing handlers.
struct TimelineContextMenu: NSViewRepresentable {
    var menuAt: (CGPoint) -> NSMenu?
    var textRects: [CGRect] = []
    var scrollBy: ((Double) -> Void)? = nil
    func makeNSView(context: Context) -> MenuView {
        let view = MenuView(); view.menuAt = menuAt; view.textRects = textRects; view.scrollBy = scrollBy; return view
    }
    func updateNSView(_ view: MenuView, context: Context) {
        view.menuAt = menuAt; view.scrollBy = scrollBy
        if view.textRects != textRects {
            view.textRects = textRects
            view.window?.invalidateCursorRects(for: view)
        }
    }
    final class MenuView: NSView {
        var menuAt: (CGPoint) -> NSMenu? = { _ in nil }
        var textRects: [CGRect] = []
        var scrollBy: ((Double) -> Void)?
        private var wheelMonitor: Any?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor); self.wheelMonitor = nil }
            guard window != nil else { return }
            // Observe before NSTextView/SwiftUI can consume the wheel, including
            // while editing a cue. Scope strictly to this visible band/window.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let scrollBy = self.scrollBy,
                      self.window === event.window,
                      self.window?.attachedSheet == nil, !self.isHiddenOrHasHiddenAncestor,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      event.scrollingDeltaY != 0 else { return event }
                // Discrete wheels can report several scroll lines for one
                // notch. Use its direction, not that accelerated line count.
                let steps = event.hasPreciseScrollingDeltas
                    ? -Double(event.scrollingDeltaY) / 10
                    : (event.scrollingDeltaY < 0 ? 1.0 : -1.0)
                scrollBy(steps)
                return nil
            }
        }
        deinit {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        }
        override func resetCursorRects() {
            super.resetCursorRects()
            for rect in textRects {
                let visible = bounds.intersection(rect)
                if !visible.isEmpty { addCursorRect(visible, cursor: .iBeam) }
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(convert(point, from: superview)), let event = NSApp.currentEvent else { return nil }
            return event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) ? self : nil
        }
        override func rightMouseDown(with event: NSEvent) {
            guard let menu = menuAt(convert(event.locationInWindow, from: nil)) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
        override func mouseDown(with event: NSEvent) { rightMouseDown(with: event) }
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

@MainActor
enum PhraseContextMenu {
    static func make(cue: Cue, sign: SyncSign?, perform: @escaping (EditorAction) -> Void) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        func item(_ title: String, _ action: EditorAction, enabled: Bool = true) -> NSMenuItem {
            ActionMenuItem(title, enabled: enabled) { perform(action) }
        }
        menu.addItem(item("Supprimer la phrase", .deletePhrase))
        let tracks = NSMenu(); tracks.autoenablesItems = false
        tracks.addItem(item("Piste précédente", .moveTrack(cue.track - 1), enabled: cue.track > 0))
        tracks.addItem(item("Piste suivante", .moveTrack(cue.track + 1), enabled: cue.track < 3))
        tracks.addItem(.separator())
        for track in 0..<4 {
            let choice = item("Piste \(track + 1)", .moveTrack(track)); choice.state = cue.track == track ? .on : .off
            tracks.addItem(choice)
        }
        let trackItem = NSMenuItem(title: "Changer de piste", action: nil, keyEquivalent: ""); trackItem.submenu = tracks; menu.addItem(trackItem)
        menu.addItem(item("Changer rôle…", .changeRole))
        let voice = item("Voix off", .voiceOff); voice.state = cue.voice == "off" ? .on : .off; menu.addItem(voice)
        menu.addItem(item("Décrocher tous les signes", .detachSigns))
        menu.addItem(.separator())
        menu.addItem(item("Couper", .cutPhrase))
        menu.addItem(item("Copier", .copyPhrase))
        menu.addItem(item("Coller", .pastePhrase, enabled: NSPasteboard.general.data(forType: NSPasteboard.PasteboardType("org.cappella-rewrite.phrase")) != nil))
        menu.addItem(.separator())
        let internalSign = sign.map { !$0.kind.hasPrefix("in_") && !$0.kind.hasPrefix("out_") } ?? false
        menu.addItem(item("Supprimer le signe", .deleteSign, enabled: internalSign))
        menu.addItem(item("Décrocher le signe", .detachSign, enabled: internalSign))
        let types = NSMenu(); types.autoenablesItems = false
        let choices: [(String, String)]
        if sign?.kind.hasPrefix("in_") == true { choices = [("Lèvres ouvertes", "in_open"), ("Lèvres fermées", "in_close")] }
        else if sign?.kind.hasPrefix("out_") == true { choices = [("Lèvres ouvertes", "out_open"), ("Lèvres fermées", "out_close")] }
        else { choices = [("Labiale m, b, p", "mpb"), ("Demi-labiale f, v, r", "fvr"), ("Neutre", "neutral"), ("Cul de poule", "weuque"), ("Grande ouverture A", "a"), ("Ouverture en rond O", "o")] }
        for (title, kind) in choices {
            let choice = item(title, .changeSignType(kind)); choice.state = sign?.kind == kind ? .on : .off; types.addItem(choice)
        }
        let typeItem = NSMenuItem(title: "Changer le type", action: nil, keyEquivalent: ""); typeItem.submenu = types; typeItem.isEnabled = sign != nil; menu.addItem(typeItem)
        return menu
    }
}
