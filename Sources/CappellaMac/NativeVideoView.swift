import SwiftUI
import AppKit
import AVKit

/// Uses the AppKit player directly. A visual offset uses a muted player so
/// adjusting the main screen never shifts the soundtrack or the timeline.
struct NativeVideoView: NSViewRepresentable {
    let player: AVPlayer
    var timeOffset = 0.0

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.controlsStyle = .none
        view.showsFrameSteppingButtons = true
        view.showsSharingServiceButton = false
        context.coordinator.configure(view, source: player, offset: timeOffset)
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.configure(view, source: player, offset: timeOffset)
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop(); view.player = nil
    }

    final class Coordinator {
        private let shifted = AVPlayer()
        private weak var source: AVPlayer?
        private weak var sourceItem: AVPlayerItem?
        private var offset = 0.0
        private var timer: Timer?
        private var seeking = false
        private var generation = UUID()
        func configure(_ view: AVPlayerView, source: AVPlayer, offset: Double) {
            let changed = self.source !== source || self.offset != offset
            self.source = source; self.offset = offset
            if offset == 0 {
                stop()
                if view.player !== source { view.player = source }
                return
            }
            shifted.isMuted = true
            if view.player !== shifted { view.player = shifted }
            if timer == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(timer, forMode: .common); self.timer = timer
            }
            tick(force: changed)
        }
        private func tick(force: Bool = false) {
            guard let source else { return }
            if source.currentItem !== sourceItem {
                generation = UUID(); seeking = false
                shifted.pause(); shifted.currentItem?.cancelPendingSeeks()
                sourceItem = source.currentItem
                shifted.replaceCurrentItem(with: sourceItem.map { AVPlayerItem(asset: $0.asset) })
            }
            guard shifted.currentItem != nil else { return }
            let position = source.currentTime().seconds
            guard position.isFinite else { return }
            let duration = source.currentItem?.duration.seconds ?? .nan
            let target = max(0, duration.isFinite ? min(position + offset, duration) : position + offset)
            let displayed = shifted.currentTime().seconds
            let tolerance = source.rate == 0 ? 0.01 : 0.08
            if !seeking && (force || !displayed.isFinite || abs(displayed - target) > tolerance) {
                seeking = true
                let token = generation
                shifted.seek(to: CMTime(seconds: target, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.generation == token else { return }
                        self.seeking = false
                    }
                }
            }
            if shifted.rate != source.rate {
                if source.rate > 0 { shifted.playImmediately(atRate: source.rate) }
                else { shifted.pause() }
            }
        }
        func stop() {
            timer?.invalidate(); timer = nil; generation = UUID(); seeking = false
            shifted.pause(); shifted.replaceCurrentItem(with: nil); sourceItem = nil
        }
        deinit { timer?.invalidate() }
    }
}
