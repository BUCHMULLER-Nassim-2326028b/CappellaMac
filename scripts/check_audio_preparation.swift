import AVFoundation

@main
struct AudioPreparationCheck {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "CappellaAudioCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func writeMono(_ url: URL, value: Float) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4800)!
        buffer.frameLength = 4800
        for i in 0..<4800 { buffer.floatChannelData![0][i] = value }
        try file.write(from: buffer)
    }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-audio-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = AVMutableComposition()
        for channel in 0..<4 {
            let url = directory.appendingPathComponent("\(channel).caf")
            try writeMono(url, value: Float(channel + 1) / 10)
            let source = AVURLAsset(url: url)
            let track = try await source.loadTracks(withMediaType: .audio)[0]
            let target = asset.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            let delay = channel == 3 ? CMTime(value: 48, timescale: 48000) : .zero
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: try await source.load(.duration)), of: track, at: delay)
        }
        guard let prepared = try await StereoAudioPreparation.prepareIfNeeded(asset: asset) else {
            throw NSError(domain: "CappellaAudioCheck", code: 2)
        }
        try require(prepared.versions.count == 2, "Deux versions stéréo attendues")
        for version in 0..<2 {
            let file = try AVAudioFile(forReading: prepared.versions[version], commonFormat: .pcmFormatFloat32, interleaved: false)
            try require(file.processingFormat.channelCount == 2, "La version doit être stéréo")
            let expectedLength: AVAudioFramePosition = version == 0 ? 4800 : 4848
            try require(file.length == expectedLength, "La durée et le retard initial doivent être conservés : \(file.length)")
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(expectedLength))!
            try file.read(into: buffer)
            for side in 0..<2 {
                let channel = version * 2 + side
                let delay = channel == 3 ? 48 : 0
                for i in 0..<Int(buffer.frameLength) {
                    let expected: Float = i >= delay && i < delay + 4800 ? Float(channel + 1) / 10 : 0
                    try require(abs(buffer.floatChannelData![side][i] - expected) < 0.0001,
                        "Fuite, inversion ou désynchronisation sur version \(version), canal \(side), échantillon \(i)")
                }
            }
        }
        print("Audio : ordre VO/VI, gauche/droite, silence et alignement des pistes vérifiés.")
    }
}
