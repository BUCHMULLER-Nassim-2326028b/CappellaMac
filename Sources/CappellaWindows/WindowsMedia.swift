import Foundation
import UWP
import WinUI
import WindowsFoundation

final class WindowsMedia {
    let video = MediaPlayer()
    let externalAudio = MediaPlayer()
    let viAudio = MediaPlayer()
    private var hasSeparateVI = false
    private var soundItem: MediaPlaybackItem?
    var usingExternalAudio = false
    var usingVI = false
    var volume = 1.0
    var muted = false
    var playbackChanged: (() -> Void)?
    var rate = 0.0 { didSet { if rate != oldValue { playbackChanged?() } } }
    var failed: ((String) -> Void)?
    private(set) var hasMedia = false
    private(set) var hasVideo = false
    var clock: MediaPlayer { hasVideo ? video : externalAudio }
    var isAdvancing: Bool { clock.playbackSession.playbackState == .playing }
    var duration: Double { Double(clock.playbackSession.naturalDuration.duration) / 10_000_000 }
    var position: Double { Double(clock.playbackSession.position.duration) / 10_000_000 }

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
        stop(); video.source = nil; externalAudio.source = nil; viAudio.source = nil; hasSeparateVI = false; soundItem = nil; hasMedia = false
        usingExternalAudio = false; hasVideo = false
        if let path = videoPath, FileManager.default.fileExists(atPath: path) {
            let source = try MediaSource.createFromUri(Uri(URL(fileURLWithPath: path).absoluteString))
            let item = MediaPlaybackItem(source)
            video.source = item; soundItem = item; hasMedia = true; hasVideo = true
        }
        if let path = audioPath, !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path) else {
                throw NSError(domain: "CappellaAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Fichier audio introuvable : " + path])
            }
            let prepared = try WindowsAudioPreparation.prepare(URL(fileURLWithPath: path))
            let source = try MediaSource.createFromUri(Uri(prepared[0].absoluteString))
            let item = MediaPlaybackItem(source)
            externalAudio.source = item; soundItem = item; usingExternalAudio = true; hasMedia = true
            if prepared.count == 2 {
                viAudio.source = MediaPlaybackItem(try MediaSource.createFromUri(Uri(prepared[1].absoluteString)))
                hasSeparateVI = true
            }
        }
        applyAudio()
    }
    func seek(_ seconds: Double) {
        let position = TimeSpan(duration: Int64(max(0, seconds) * 10_000_000))
        if hasVideo { video.playbackSession.position = position }
        if usingExternalAudio { externalAudio.playbackSession.position = position }; if hasSeparateVI { viAudio.playbackSession.position = position }
    }
    func setRate(_ value: Double) throws {
        rate = value
        if value > 0 {
            if hasVideo { video.playbackSession.playbackRate = value; try video.play() }
            if usingExternalAudio { externalAudio.playbackSession.playbackRate = value; try externalAudio.play() }; if hasSeparateVI { viAudio.playbackSession.playbackRate = value; try viAudio.play() }
        } else {
            try video.pause(); try externalAudio.pause(); try viAudio.pause()
        }
    }
    func stop() { rate = 0; try? video.pause(); try? externalAudio.pause(); try? viAudio.pause() }
    func toggleVI() {
        usingVI.toggle(); applyAudio()
    }
    func applyAudio() {
        video.isMuted = muted || usingExternalAudio
        externalAudio.isMuted = muted || (hasSeparateVI && usingVI)
        viAudio.isMuted = muted || !usingVI
        video.volume = volume; externalAudio.volume = volume; viAudio.volume = volume
        if !hasSeparateVI, let tracks = soundItem?.audioTracks, tracks.size >= 2 {
            tracks.selectedIndex = usingVI ? 1 : 0
        }
    }
}
