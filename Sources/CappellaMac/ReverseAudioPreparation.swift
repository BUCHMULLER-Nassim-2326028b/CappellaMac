import AVFoundation

/// Reversed PCM tracks retain their original channel layout and presentation
/// duration. A bounded buffer keeps long films out of RAM.
final class ReverseAudioPreparation {
    let directory: URL
    let composition = AVMutableComposition()
    private(set) var tracks: [(track: AVAssetTrack, offset: Int, count: Int)] = []
    private(set) var channelCount = 0
    private init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-reverse-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func prepare(asset: AVAsset) async throws -> ReverseAudioPreparation {
        let result = try ReverseAudioPreparation()
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
        for (index, track) in sourceTracks.enumerated() {
            try Task.checkCancellation()
            let descriptions = try await track.load(.formatDescriptions)
            guard let description = descriptions.first,
                  let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let channels = Int(format.pointee.mChannelsPerFrame)
            guard channels > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let decoded = result.directory.appendingPathComponent("decoded.caf")
            let reversed = result.directory.appendingPathComponent("reverse-\(index).caf")
            try StereoAudioPreparation.decode(asset: asset, track: track, to: decoded, channels: channels, duration: duration)
            try reverse(decoded, to: reversed)
            try FileManager.default.removeItem(at: decoded)
            let source = AVURLAsset(url: reversed)
            guard let original = try await source.loadTracks(withMediaType: .audio).first,
                  let target = result.composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 48000))
            try target.insertTimeRange(range, of: original, at: .zero)
            result.tracks.append((target, result.channelCount, channels))
            result.channelCount += channels
        }
        return result
    }

    private static func reverse(_ source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let output = try AVAudioFile(forWriting: destination, settings: input.fileFormat.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 48000) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var end = input.length
        while end > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(48000, end))
            input.framePosition = end - AVAudioFramePosition(count)
            try input.read(into: buffer, frameCount: count)
            guard buffer.frameLength == count else { throw CocoaError(.fileReadCorruptFile) }
            for channel in 0..<Int(input.processingFormat.channelCount) {
                let samples = buffer.floatChannelData![channel]
                for index in 0..<(Int(count) / 2) {
                    let opposite = Int(count) - index - 1
                    let saved = samples[index]; samples[index] = samples[opposite]; samples[opposite] = saved
                }
            }
            try output.write(from: buffer)
            end -= AVAudioFramePosition(count)
        }
    }
}
