import AVFoundation
import Combine
import AppKit
import CappellaCore

/// One timeline for the editor, with or without an attached video.
/// Reverse sound uses a separate PCM player; video follows its audio clock.
final class Transport: ObservableObject {
    let player = AVPlayer()
    private var videoURL: URL?
    private var soundURL: URL?
    private var routingTracks: [(track: AVAssetTrack, offset: Int, count: Int)] = []
    private var channelCount = 0
    private var preparedAudio: StereoAudioPreparation?
    private let reversePlayer = AVPlayer()
    private var reverseAudio: ReverseAudioPreparation?
    private var reverseTask: Task<Void, Never>?
    private var reverseObservation: NSKeyValueObservation?
    private var reverseGeneration = UUID()
    private var reverseSeekGeneration = UUID()
    private var reverseSeeking = false
    private var reverseFailure: String?
    @Published var preparingAudio = false
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
    private var scopedURLs: [URL] = []
    private var loadTask: Task<Void, Never>?
    private var seekInFlight = false
    private var queuedSeek: Double?
    private var seekGeneration = UUID()

    init() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date(); let elapsed = min(0.1, now.timeIntervalSince(previousTick)); previousTick = now
        guard rate != 0 else { return }
        if rate < 0, channelCount > 0, player.currentItem != nil {
            guard reverseAudio != nil, !reverseSeeking else {
                // Keep shuttling while PCM is prepared or positioned. The
                // reverse player joins at the latest timeline position.
                seconds = max(0, seconds + elapsed * Double(rate))
                requestMediaSeek(seconds)
                if seconds == 0 { setRate(0) }
                return
            }
            let position = reversePlayer.currentTime().seconds
            if position.isFinite { seconds = max(0, duration - position) }
            requestMediaSeek(seconds)
            if seconds <= 0 { setRate(0) }
            return
        }
        guard !seekInFlight else { return }
        if player.currentItem != nil && rate > 0 {
            let position = player.currentTime().seconds
            if position.isFinite { seconds = max(0, position) }
            if duration > 0 && seconds >= duration - 0.015 { setRate(0) }
        } else {
            seconds = max(0, seconds + elapsed * Double(rate))
            if player.currentItem != nil {
                requestMediaSeek(seconds)
            }
            if seconds == 0 && rate < 0 { setRate(0) }
        }
    }

    func close() {
        loadTask?.cancel(); loadTask = nil; setRate(0); clearReverseAudio()
        resetMediaSeeks()
        player.replaceCurrentItem(with: nil); itemObservation = nil; preparedAudio = nil
        videoURL = nil; soundURL = nil; routingTracks.removeAll(); channelCount = 0
        seconds = 0; duration = 0; mediaName = nil; hasVI = false; usingVI = false; preparingAudio = false
        mediaID = UUID(); error = nil
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }; scopedURLs.removeAll()
    }

    func open(_ url: URL, sound: URL? = nil) {
        videoURL = url; soundURL = sound; loadMedia()
    }

    /// Sound replaces the movie soundtrack, including all VO/VI channels.
    func openSound(_ url: URL) { soundURL = url; loadMedia() }

    private func loadMedia() {
        let savedRate = rate; let savedPosition = seconds
        loadTask?.cancel(); setRate(0); clearReverseAudio(); error = nil; hasVI = false; preparingAudio = true
        let image = videoURL; let sound = soundURL
        for url in [image, sound].compactMap({ $0 }) {
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        }
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.preparingAudio = false } }
            do {
                let composition = AVMutableComposition()
                let movie = image.map { AVURLAsset(url: $0) }
                if let movie {
                    for track in try await movie.loadTracks(withMediaType: .video) {
                        guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                        let range = try await track.load(.timeRange)
                        try target.insertTimeRange(range, of: track, at: range.start)
                        target.preferredTransform = try await track.load(.preferredTransform)
                    }
                }
                let audio = sound.map { AVURLAsset(url: $0) } ?? movie
                var prepared: StereoAudioPreparation?
                if let audio {
                    let worker = Task.detached { try await StereoAudioPreparation.prepareIfNeeded(asset: audio) }
                    prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    let sources: [AVAsset]
                    if let prepared { sources = prepared.versions.map { AVURLAsset(url: $0) } }
                    else { sources = [audio] }
                    for source in sources {
                        for track in try await source.loadTracks(withMediaType: .audio) {
                            guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                            let range = try await track.load(.timeRange)
                            try target.insertTimeRange(range, of: track, at: range.start)
                        }
                    }
                }
                try Task.checkCancellation()
                let item = AVPlayerItem(asset: composition)
                try await self.configureAudio(asset: composition, item: item)
                try Task.checkCancellation()
                self.itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Lecture du média impossible."
                    DispatchQueue.main.async { self?.error = message; self?.setRate(0) }
                }
                self.resetMediaSeeks()
                self.player.replaceCurrentItem(with: item)
                self.preparedAudio = prepared
                let duration = composition.duration.seconds
                self.duration = duration.isFinite ? max(0, duration) : 0
                self.mediaName = image?.lastPathComponent ?? sound?.lastPathComponent
                self.mediaID = UUID(); self.seek(seconds: savedPosition); self.setRate(savedRate)
                self.prepareReverseAudio()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    @MainActor private func configureAudio(asset: AVAsset, item: AVPlayerItem) async throws {
        var tracks: [(track: AVAssetTrack, offset: Int, count: Int)] = []
        var offset = 0
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let descriptions = try await track.load(.formatDescriptions)
            var count = 0
            if let description = descriptions.first, let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                count = Int(format.pointee.mChannelsPerFrame)
            }
            tracks.append((track, offset, count)); offset += count
        }
        guard !Task.isCancelled else { return }
        routingTracks = tracks; channelCount = offset; hasVI = offset == 2 || offset == 4
        if !hasVI { usingVI = false }
        try applyRouting(to: item); updateAudio()
    }

    private func applyRouting(to item: AVPlayerItem,
                              tracks: [(track: AVAssetTrack, offset: Int, count: Int)]? = nil,
                              total: Int? = nil) throws {
        let selected = Set(AudioRouting.selectedChannels(total: total ?? channelCount, international: usingVI))
        var parameters: [AVMutableAudioMixInputParameters] = []
        for source in tracks ?? routingTracks {
            let input = AVMutableAudioMixInputParameters(track: source.track)
            let local = (0..<source.count).filter { selected.contains(source.offset + $0) }
            if local.isEmpty { input.setVolume(0, at: .zero) }
            else if source.count > 1 && local.count != source.count {
                input.audioTapProcessor = try AudioChannelTap.make(channels: local)
            }
            parameters.append(input)
        }
        let mix = AVMutableAudioMix(); mix.inputParameters = parameters; item.audioMix = mix
    }

    func seek(frame: Int, fps: Int) { seek(seconds: Double(max(0, frame)) / Double(fps)) }
    func seek(seconds target: Double) {
        guard target.isFinite else { return }
        seconds = max(0, duration > 0 ? min(target, duration) : target)
        requestMediaSeek(seconds)
        if rate < 0 { seekReverseAudio() }
        previousTick = Date()
    }

    /// The logical position changes immediately for every key press. Decode
    /// only the latest requested position once the current seek completes.
    private func requestMediaSeek(_ target: Double) {
        guard player.currentItem != nil else { return }
        if seekInFlight { queuedSeek = target; return }
        seekInFlight = true
        let generation = seekGeneration
        player.seek(to: CMTime(seconds: target, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.seekGeneration == generation else { return }
                self.seekInFlight = false
                if let next = self.queuedSeek {
                    self.queuedSeek = nil
                    self.requestMediaSeek(next)
                }
            }
        }
    }

    private func resetMediaSeeks() {
        seekGeneration = UUID(); seekInFlight = false; queuedSeek = nil
        player.currentItem?.cancelPendingSeeks()
    }

    private func clearReverseAudio() {
        reverseGeneration = UUID(); reverseSeekGeneration = UUID()
        reverseTask?.cancel(); reverseTask = nil; reverseSeeking = false
        reversePlayer.pause(); reversePlayer.currentItem?.cancelPendingSeeks()
        reversePlayer.replaceCurrentItem(with: nil); reverseObservation = nil; reverseAudio = nil; reverseFailure = nil
    }

    private func prepareReverseAudio() {
        guard channelCount > 0, let asset = player.currentItem?.asset,
              reverseAudio == nil, reverseTask == nil, reverseFailure == nil else { return }
        let generation = reverseGeneration
        reverseTask = Task { @MainActor [weak self] in
            do {
                let worker = Task.detached(priority: .utility) { try await ReverseAudioPreparation.prepare(asset: asset) }
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard let self, self.reverseGeneration == generation else { return }
                let item = AVPlayerItem(asset: prepared.composition)
                try self.applyRouting(to: item, tracks: prepared.tracks, total: prepared.channelCount)
                self.reverseAudio = prepared; self.reverseTask = nil
                self.reverseObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Lecture du son inversé impossible."
                    DispatchQueue.main.async {
                        guard let self, self.reverseGeneration == generation else { return }
                        self.reverseAudioFailed(message)
                    }
                }
                self.reversePlayer.replaceCurrentItem(with: item)
                if self.rate < 0 { self.seekReverseAudio() }
            } catch {
                guard let self, !Task.isCancelled, self.reverseGeneration == generation else { return }
                self.reverseTask = nil
                self.reverseAudioFailed(error.localizedDescription)
            }
        }
    }

    private func reverseAudioFailed(_ message: String) {
        let reversing = rate < 0
        if reversing { setRate(0) }
        clearReverseAudio()
        reverseFailure = message
        if reversing { error = message }
    }

    private func seekReverseAudio() {
        guard reverseAudio != nil, rate < 0 else { return }
        reversePlayer.pause()
        reversePlayer.currentItem?.cancelPendingSeeks()
        reverseSeeking = true
        let generation = UUID(); reverseSeekGeneration = generation
        let target = CMTime(seconds: max(0, duration - seconds), preferredTimescale: 48000)
        reversePlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            DispatchQueue.main.async {
                guard let self, self.reverseSeekGeneration == generation else { return }
                if !completed {
                    self.setRate(0); self.error = "Positionnement du son inversé impossible."
                    return
                }
                self.reverseSeeking = false
                if self.rate < 0 { self.reversePlayer.playImmediately(atRate: abs(self.rate)) }
            }
        }
    }

    func setRate(_ value: Float) {
        if value < 0, let message = reverseFailure { error = message; return }
        if rate > 0, player.currentItem != nil {
            let position = player.currentTime().seconds
            if position.isFinite { seconds = max(0, position) }
        } else if rate < 0, reverseAudio != nil, !reverseSeeking {
            let position = reversePlayer.currentTime().seconds
            if position.isFinite { seconds = max(0, duration - position) }
        }
        reversePlayer.pause()
        reverseSeekGeneration = UUID(); reverseSeeking = false
        rate = value; previousTick = Date(); updateAudio()
        if value > 0 {
            requestMediaSeek(seconds)
            player.playImmediately(atRate: value)
        } else {
            player.pause()
            if value < 0 {
                if reverseAudio != nil { seekReverseAudio() }
                else { prepareReverseAudio() }
            } else { requestMediaSeek(seconds) }
        }
    }
    func toggle() { setRate(rate == 0 ? 1 : 0) }
    func toggleVI() {
        guard hasVI, let item = player.currentItem else { error = "Le média doit contenir deux canaux (VO/VI mono) ou quatre canaux (VO/VI stéréo)."; return }
        usingVI.toggle()
        do {
            try applyRouting(to: item)
            if let reverse = reverseAudio, let reverseItem = reversePlayer.currentItem {
                try applyRouting(to: reverseItem, tracks: reverse.tracks, total: reverse.channelCount)
            }
        } catch {
            usingVI.toggle()
            try? applyRouting(to: item)
            if let reverse = reverseAudio, let reverseItem = reversePlayer.currentItem {
                try? applyRouting(to: reverseItem, tracks: reverse.tracks, total: reverse.channelCount)
            }
            self.error = error.localizedDescription
        }
        updateAudio()
    }
    func toggleMute() { muted.toggle(); updateAudio() }
    func changeVolume(_ delta: Float) { volume = min(1, max(0, volume + delta)); updateAudio() }
    private func updateAudio() {
        player.isMuted = muted || rate < 0
        player.volume = volume
        reversePlayer.isMuted = muted || rate >= 0
        reversePlayer.volume = volume
    }
    deinit {
        timer?.invalidate(); loadTask?.cancel(); reverseTask?.cancel()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
