import SwiftUI
import AppKit
import AVKit

/// Uses the AppKit player directly. Avoids instantiating SwiftUI VideoPlayer's
/// generic _AVKit_SwiftUI view, which aborts in the reported macOS 26.5 stack.
struct NativeVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.controlsStyle = .inline
        view.showsFrameSteppingButtons = true
        view.showsSharingServiceButton = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        // The transport owns the player; detaching a view must not stop it.
        view.player = nil
    }
}
