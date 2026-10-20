import AVFoundation
import CappellaCore

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

    private func append(_ url: URL, duration: Double) async throws {
        let source = AVURLAsset(url: url)
        guard let original = try await source.loadTracks(withMediaType: .audio).first,
              let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let description = try await original.load(.formatDescriptions).first,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { throw CocoaError(.fileReadCorruptFile) }
        let channels = Int(format.pointee.mChannelsPerFrame)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 48000))
        try target.insertTimeRange(range, of: original, at: .zero)
        tracks.append((target, channelCount, channels)); channelCount += channels
    }
    static func prepare(asset: AVAsset, pcmSource: URL? = nil) async throws -> ReverseAudioPreparation {
        let result = try ReverseAudioPreparation()
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        if let source = pcmSource, ["wav", "aif", "aiff", "aifc"].contains(source.pathExtension.lowercased()) {
            do {
                let cache = try PCMPlaybackCache.prepare([source], routeChannels: false, minimumDuration: duration)
                for (url, seconds) in zip(cache.reverse, cache.durations) {
                    try await result.append(url, duration: seconds)
                }
                return result
            } catch is CancellationError { throw CancellationError() }
            catch { /* Compressed PCM containers fall back to AVFoundation. */ }
        }
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
            let decoded = result.directory.appendingPathComponent("decoded.wav")
            try StereoAudioPreparation.decode(asset: asset, track: track, to: decoded, channels: channels, duration: duration)
            let folder = result.directory.appendingPathComponent("reverse-\(index)")
            guard let reversed = try PCMChannelPreparation.prepare([decoded], in: folder, reverse: true, routeChannels: false).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.removeItem(at: decoded)
            try await result.append(reversed, duration: duration)
        }
        return result
    }

}
