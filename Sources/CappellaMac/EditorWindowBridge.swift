import SwiftUI
import AppKit
import CappellaSession

private final class DelegateReference: @unchecked Sendable {
    // AppKit accesses this reference on its main thread. The reference box also
    // lets NSObject's nonisolated forwarding methods preserve SwiftUI's delegate.
    weak var value: NSWindowDelegate?
}

/// Keep SwiftUI's scene delegate for its normal lifecycle while adding the
/// unsaved-work check to the window's close button.
struct EditorWindowBridge: NSViewRepresentable {
    @ObservedObject var session: ProjectSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateNSView(_ view: AttachmentView, context: Context) {
        if let window = view.window { context.coordinator.attach(to: window) }
    }
    final class AttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { attach?(window) } }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let session: ProjectSession
        nonisolated private let delegateReference = DelegateReference()
        init(session: ProjectSession) { self.session = session }
        func attach(to window: NSWindow) {
            if window.delegate !== self { delegateReference.value = window.delegate; window.delegate = self }
            session.attach(window: window)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard session.requestClose() else { return false }
            guard delegateReference.value?.windowShouldClose?(sender) != false else { return false }
            session.approveWindowClose(); return true
        }
        nonisolated override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || delegateReference.value?.responds(to: selector) == true }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            if delegateReference.value?.responds(to: selector) == true { return delegateReference.value }
            return super.forwardingTarget(for: selector)
        }
    }
}
