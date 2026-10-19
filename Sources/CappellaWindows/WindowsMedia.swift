import Foundation
import UWP
import WinUI
import WindowsFoundation

final class WindowsMedia {
    let video = MediaPlayer()
    let externalAudio = MediaPlayer()
    let viAudio = MediaPlayer()
    private var hasSeparateVI = false
    private var disposed = false
    private var soundItem: MediaPlaybackItem?
    private var audioSources: [URL] = []
    private var reverseTask: Task<Void, Never>?
    private var reverseGeneration = UUID()
    private var reverseAudio: WindowsReverseAudio?
    private var reversePlayers: [MediaPlayer] = []
    private var reverseReady: Set<Int> = []
    private var reversePrepared = false
    private var reverseFailure: String?
    private var requestedPosition = 0.0
    private var lastReverseVideoPosition: Double?
    var usingExternalAudio = false
    var usingVI = false
    var videoOffset = 0.0
    var volume = 1.0
    var muted = false
    var playbackChanged: (() -> Void)?
    var rate = 0.0 { didSet { if rate != oldValue { playbackChanged?() } } }
    var failed: ((String) -> Void)?
    private(set) var hasMedia = false
    private(set) var hasVideo = false
    var clock: MediaPlayer { usingExternalAudio || !hasVideo ? externalAudio : video }
    private var reverseClockIndex: Int { usingVI && reversePlayers.count > 1 ? 1 : 0 }
    var waitingForReverseAudio: Bool {
        rate < 0 && (!reversePrepared || reverseReady.count < reversePlayers.count)
    }
    var usesPlaybackClock: Bool { rate > 0 || !reversePlayers.isEmpty }
    var isAdvancing: Bool {
        if rate < 0 {
            guard !waitingForReverseAudio, !reversePlayers.isEmpty else { return false }
            return reversePlayers[reverseClockIndex].playbackSession.playbackState == .playing
        }
        return clock.playbackSession.playbackState == .playing
    }
    var duration: Double { Double(clock.playbackSession.naturalDuration.duration) / 10_000_000 }
    var position: Double {
        if rate < 0 {
            guard !waitingForReverseAudio, let audio = reverseAudio, !reversePlayers.isEmpty else { return requestedPosition }
            let index = reverseClockIndex
            let reversed = Double(reversePlayers[index].playbackSession.position.duration) / 10_000_000
            return max(0, audio.durations[index] - reversed - (usingExternalAudio ? 0 : videoOffset))
        }
        let seconds = Double(clock.playbackSession.position.duration) / 10_000_000
        return usingExternalAudio || !hasVideo ? seconds : max(0, seconds - videoOffset)
    }

    init() {
        video.autoPlay = false; externalAudio.autoPlay = false; viAudio.autoPlay = false
        connectAudioEvents()
        video.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture vidéo impossible.") }
        }
        externalAudio.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture audio impossible.") }
        }
    }
    private func connectAudioEvents() {
        viAudio.mediaFailed.addHandler { [weak self] _, args in
            DispatchQueue.main.async { self?.failed?(args?.errorMessage ?? "Lecture VI impossible.") }
        }
        for player in [video, externalAudio, viAudio] {
            player.mediaOpened.addHandler { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyAudio() }
            }
        }
    }
    func open(videoPath: String?, audioPath: String?) throws {
        unload()
        if let path = videoPath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let source = try MediaSource.createFromUri(Uri(url.absoluteString))
            let item = MediaPlaybackItem(source)
            video.source = item; soundItem = item; hasMedia = true; hasVideo = true
            audioSources = [url]
        }
        if let path = audioPath, !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path) else {
                throw NSError(domain: "CappellaAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fichier audio introuvable : " + path])
            }
            let prepared = try WindowsAudioPreparation.prepare(URL(fileURLWithPath: path))
            audioSources = prepared
            let source = try MediaSource.createFromUri(Uri(prepared[0].absoluteString))
            let item = MediaPlaybackItem(source)
            externalAudio.source = item; soundItem = item; usingExternalAudio = true; hasMedia = true
            if prepared.count == 2 {
                viAudio.source = MediaPlaybackItem(try MediaSource.createFromUri(Uri(prepared[1].absoluteString)))
                hasSeparateVI = true
            }
        }
        applyAudio()
        prepareReverseAudio()
    }
    private func clearReverseAudio() {
        reverseGeneration = UUID(); reverseTask?.cancel(); reverseTask = nil
        for player in reversePlayers { try? player.pause(); player.source = nil; try? player.close() }
        reversePlayers.removeAll(); reverseReady.removeAll()
        reverseAudio = nil; reversePrepared = false; reverseFailure = nil
    }
    func unload() {
        guard !disposed else { return }
        stop(); clearReverseAudio()
        video.source = nil; externalAudio.source = nil; viAudio.source = nil
        soundItem = nil; hasSeparateVI = false; audioSources = []; requestedPosition = 0; lastReverseVideoPosition = nil
        usingExternalAudio = false; usingVI = false; hasVideo = false; hasMedia = false
    }
    /// Backward video seeks must not interrupt the independent audio clock.
    func synchronizeReverseVideo(_ seconds: Double) {
        guard !disposed else { return }
        requestedPosition = seconds
        if hasVideo {
            let target = max(0, seconds + videoOffset)
            guard lastReverseVideoPosition != target else { return }
            lastReverseVideoPosition = target
            video.playbackSession.position = TimeSpan(duration: Int64(target * 10_000_000))
        }
    }
    func seek(_ seconds: Double) {
        guard !disposed else { return }
        requestedPosition = max(0, seconds)
        lastReverseVideoPosition = nil
        synchronizeReverseVideo(requestedPosition)
        let position = TimeSpan(duration: Int64(requestedPosition * 10_000_000))
        if usingExternalAudio { externalAudio.playbackSession.position = position }
        if hasSeparateVI { viAudio.playbackSession.position = position }
        if rate < 0 { seekReverseAudio(); startReverseAudio() }
    }
    private func seekReverseAudio() {
        guard let audio = reverseAudio else { return }
        let original = requestedPosition + (usingExternalAudio ? 0 : videoOffset)
        for (index, player) in reversePlayers.enumerated() where reverseReady.contains(index) {
            try? player.pause()
            let reversed = max(0, min(audio.durations[index], audio.durations[index] - original))
            // MediaPlayer queues the seek before Play, as in forward playback.
            // Waiting for SeekCompleted here can stall a direction change.
            player.playbackSession.position = TimeSpan(duration: Int64(reversed * 10_000_000))
        }
    }
    private func prepareReverseAudio() {
        guard !reversePrepared, reverseTask == nil, reverseFailure == nil else { return }
        guard !audioSources.isEmpty else { reversePrepared = true; return }
        let generation = reverseGeneration, sources = audioSources
        reverseTask = Task { @MainActor [weak self] in
            do {
                let worker = Task.detached(priority: .utility) { try WindowsReverseAudio.prepare(sources: sources) }
                let audio = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard let self, !self.disposed, self.reverseGeneration == generation else { return }
                self.reverseAudio = audio; self.reversePrepared = true; self.reverseTask = nil
                for (index, url) in audio.files.enumerated() {
                    let player = MediaPlayer()
                    player.autoPlay = false
                    self.reversePlayers.append(player)
                    player.mediaOpened.addHandler { [weak self] _, _ in
                        DispatchQueue.main.async {
                            guard let self, self.reverseGeneration == generation else { return }
                            self.reverseReady.insert(index)
                            self.seekReverseAudio(); self.startReverseAudio()
                        }
                    }
                    player.mediaFailed.addHandler { [weak self] _, args in
                        let message = args?.errorMessage ?? "Lecture du son inversé impossible."
                        DispatchQueue.main.async {
                            guard let self, self.reverseGeneration == generation else { return }
                            self.reverseAudioFailed(message)
                        }
                    }
                    player.source = MediaPlaybackItem(try MediaSource.createFromUri(Uri(url.absoluteString)))
                }
                self.startReverseAudio()
            } catch {
                guard let self, !Task.isCancelled, self.reverseGeneration == generation else { return }
                self.reverseTask = nil
                self.reverseAudioFailed(error.localizedDescription)
            }
        }
    }
    private func reverseAudioFailed(_ message: String) {
        let reversing = rate < 0
        if reversing { stop() }
        clearReverseAudio()
        reverseFailure = message
        // A background warm-up failure must not interrupt normal playback.
        if reversing { failed?(message) }
    }
    private func startReverseAudio() {
        guard rate < 0, !waitingForReverseAudio else { return }
        applyAudio()
        for player in reversePlayers {
            player.playbackSession.playbackRate = abs(rate)
            do { try player.play() } catch { reverseAudioFailed(error.localizedDescription); return }
        }
        playbackChanged?()
    }
    func setRate(_ value: Double) throws {
        guard !disposed else { return }
        if value < 0, let message = reverseFailure {
            throw NSError(domain: "CappellaReverseAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        // Snapshot the active clock before pausing or publishing the new
        // direction. Preparation callbacks then use this position or a newer
        // position supplied by the timeline while the audio is loading.
        let current = rate == 0 ? requestedPosition : position
        try video.pause(); try externalAudio.pause(); try viAudio.pause()
        for player in reversePlayers { try player.pause() }
        requestedPosition = max(0, current)
        rate = value
        applyAudio()
        if value < 0 {
            lastReverseVideoPosition = nil
            synchronizeReverseVideo(requestedPosition)
            prepareReverseAudio()
            seekReverseAudio()
            startReverseAudio()
        } else {
            seek(requestedPosition)
            if value > 0 {
                if hasVideo { video.playbackSession.playbackRate = value; try video.play() }
                if usingExternalAudio { externalAudio.playbackSession.playbackRate = value; try externalAudio.play() }
                if hasSeparateVI { viAudio.playbackSession.playbackRate = value; try viAudio.play() }
            }
        }
    }
    func stop() { try? setRate(0) }
    func dispose() {
        guard !disposed else { return }
        playbackChanged = nil; failed = nil
        stop(); clearReverseAudio(); disposed = true
        try? video.close(); try? externalAudio.close(); try? viAudio.close()
        soundItem = nil
    }
    func toggleVI() {
        let current = position
        usingVI.toggle()
        if rate < 0 { requestedPosition = current; seekReverseAudio(); startReverseAudio() }
        applyAudio()
    }
    func applyAudio() {
        guard !disposed else { return }
        video.isMuted = muted || usingExternalAudio || rate < 0
        externalAudio.isMuted = muted || (hasSeparateVI && usingVI) || rate < 0
        viAudio.isMuted = muted || !usingVI || rate < 0
        video.volume = volume; externalAudio.volume = volume; viAudio.volume = volume
        for (index, player) in reversePlayers.enumerated() {
            player.isMuted = muted || rate >= 0 || (reversePlayers.count > 1 && index != (usingVI ? 1 : 0))
            player.volume = volume
        }
        if !hasSeparateVI, let tracks = soundItem?.audioTracks, tracks.size >= 2 {
            tracks.selectedIndex = usingVI ? 1 : 0
        }
    }
    deinit { reverseTask?.cancel() }
}
