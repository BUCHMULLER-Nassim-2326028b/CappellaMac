import AVFoundation
import Combine
import AppKit

final class Transport: ObservableObject {
    let player = AVPlayer()
    @Published var seconds = 0.0
    @Published var duration = 0.0
    @Published var mediaName = "Aucune vidéo"
    @Published var error: String?
    private var observer: Any?
    private var itemObservation: NSKeyValueObservation?
    private var scopedURL: URL?
    private var loadTask: Task<Void, Never>?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            let value = time.seconds
            self?.seconds = value.isFinite ? max(0, value) : 0
        }
    }

    func open(_ url: URL) {
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        if let previous = scopedURL { previous.stopAccessingSecurityScopedResource() }
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        duration = 0; seconds = 0; error = nil; mediaName = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Lecture du média impossible."
            DispatchQueue.main.async { self?.error = message }
        }
        player.replaceCurrentItem(with: item)
        loadTask = Task { @MainActor [weak self] in
            do {
                let playable = try await asset.load(.isPlayable)
                let time = try await asset.load(.duration)
                guard !Task.isCancelled else { return }
                guard playable else { self?.error = "Ce média n'est pas lisible par AVFoundation."; return }
                self?.duration = time.seconds.isFinite ? max(0, time.seconds) : 0
            } catch {
                if !Task.isCancelled { self?.error = error.localizedDescription }
            }
        }
    }

    func seek(frame: Int, fps: Int) {
        let target = CMTime(seconds: Double(max(0, frame)) / Double(fps), preferredTimescale: 60000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func toggle() { player.rate == 0 ? player.play() : player.pause() }

    deinit {
        loadTask?.cancel()
        if let observer { player.removeTimeObserver(observer) }
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
    }
}
