import AVFoundation
import Combine
import AppKit

/// One timeline for the editor, with or without an attached video.
/// Negative shuttle uses frame seeking when reverse decoding is unavailable.
final class Transport: ObservableObject {
    let player = AVPlayer()
    let alternateAudio = AVPlayer()
    @Published var seconds = 0.0
    @Published var duration = 0.0
    @Published var mediaName: String?
    @Published var mediaID = UUID()
    @Published var rate: Float = 0
    @Published var usingVI = false
    @Published var hasVI = false
    @Published var muted = false
    @Published var volume: Float = 1
    @Published var error: String?
    private var timer: Timer?
    private var previousTick = Date()
    private var itemObservation: NSKeyValueObservation?
    private var audioObservation: NSKeyValueObservation?
    private var scopedURLs: [URL] = []
    private var loadTask: Task<Void, Never>?

    init() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date(); let elapsed = min(0.1, now.timeIntervalSince(previousTick)); previousTick = now
        guard rate != 0 else { return }
        if player.currentItem != nil && rate > 0 {
            let position = player.currentTime().seconds
            if position.isFinite { seconds = max(0, position) }
            if duration > 0 && seconds >= duration - 0.015 { setRate(0) }
        } else {
            seconds = max(0, seconds + elapsed * Double(rate))
            if player.currentItem != nil {
                player.seek(to: CMTime(seconds: seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            if seconds == 0 && rate < 0 { setRate(0) }
        }
    }

    func open(_ url: URL) {
        loadTask?.cancel(); setRate(0); error = nil
        if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Lecture du média impossible."
            DispatchQueue.main.async { self?.error = message; self?.setRate(0) }
        }
        player.replaceCurrentItem(with: item)
        mediaName = url.lastPathComponent; mediaID = UUID(); duration = 0
        let savedPosition = seconds
        loadTask = Task { @MainActor [weak self] in
            do {
                let playable = try await asset.load(.isPlayable)
                let time = try await asset.load(.duration)
                guard !Task.isCancelled else { return }
                guard playable else { self?.error = "Ce média n'est pas lisible par AVFoundation."; return }
                self?.duration = time.seconds.isFinite ? max(0, time.seconds) : 0
                self?.seek(seconds: savedPosition)
            } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
        }
    }

    func openVI(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        let item = AVPlayerItem(url: url)
        audioObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Lecture de la piste VI impossible."
            DispatchQueue.main.async {
                self?.hasVI = false; self?.usingVI = false; self?.updateAudio(); self?.error = message
            }
        }
        alternateAudio.replaceCurrentItem(with: item)
        hasVI = true; updateAudio(); seek(seconds: seconds)
        if rate > 0 { alternateAudio.playImmediately(atRate: rate) }
    }

    func seek(frame: Int, fps: Int) { seek(seconds: Double(max(0, frame)) / Double(fps)) }
    func seek(seconds target: Double) {
        guard target.isFinite else { return }
        seconds = max(0, duration > 0 ? min(target, duration) : target)
        let time = CMTime(seconds: seconds, preferredTimescale: 60000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        alternateAudio.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        previousTick = Date()
    }

    func setRate(_ value: Float) {
        rate = value; previousTick = Date()
        if value > 0 {
            player.playImmediately(atRate: value)
            if hasVI { alternateAudio.playImmediately(atRate: value) }
        } else { player.pause(); alternateAudio.pause() }
    }
    func toggle() { setRate(rate == 0 ? 1 : 0) }
    func toggleVI() {
        guard hasVI else { error = "Ouvrez d'abord la piste VI depuis le menu Audio."; return }
        usingVI.toggle(); updateAudio()
    }
    func toggleMute() { muted.toggle(); updateAudio() }
    func changeVolume(_ delta: Float) { volume = min(1, max(0, volume + delta)); updateAudio() }
    private func updateAudio() {
        player.isMuted = muted || usingVI; alternateAudio.isMuted = muted || !usingVI
        player.volume = volume; alternateAudio.volume = volume
    }
    deinit {
        timer?.invalidate(); loadTask?.cancel()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
