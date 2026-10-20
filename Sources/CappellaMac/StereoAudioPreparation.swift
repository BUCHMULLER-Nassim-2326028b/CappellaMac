import AVFoundation
import CappellaCore

/// AVPlayer mixes separate mono tracks to the centre. Convert four independent
/// mono tracks to two explicitly interleaved stereo pairs, once before playback.
/// Files stream through bounded PCM buffers rather than loading the film in RAM.
final class StereoAudioPreparation {
    let directory: URL
    private(set) var versions: [URL] = []
    private init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-audio-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func prepareIfNeeded(asset: AVAsset) async throws -> StereoAudioPreparation? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 4 else { return nil }
        for track in tracks {
            let descriptions = try await track.load(.formatDescriptions)
            guard let format = descriptions.first,
                  CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mChannelsPerFrame == 1 else { return nil }
        }
        let prepared = try StereoAudioPreparation()
        var mono: [URL] = []
        for (index, track) in tracks.enumerated() {
            try Task.checkCancellation()
            let url = prepared.directory.appendingPathComponent("mono-\(index).wav")
            try decode(asset: asset, track: track, to: url); mono.append(url)
        }
        // Each stereo pair keeps its own presentation duration. Padding both
        // versions to the longest of all four tracks changes the VO duration.
        for (version, channels) in AudioRouting.versions(total: mono.count).enumerated() {
            let directory = prepared.directory.appendingPathComponent("version-\(version)")
            let pair = channels.map { mono[$0] }
            let files = try PCMChannelPreparation.prepare(pair, in: directory, routeChannels: false)
            prepared.versions.append(contentsOf: files)
        }
        for url in mono { try? FileManager.default.removeItem(at: url) }
        return prepared
    }

    private static func settings(channels: Int) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
         AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 32,
         AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
         AVLinearPCMIsNonInterleaved: false]
    }

    static func decode(asset: AVAsset, track: AVAssetTrack, to url: URL, channels: Int = 1, duration: Double = 0) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings(channels: channels))
        reader.add(output)
        let file = try AVAudioFile(forWriting: url, settings: settings(channels: channels), commonFormat: .pcmFormatFloat32, interleaved: false)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        guard let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { throw CocoaError(.fileWriteUnknown) }
        for channel in 0..<channels { memset(silence.floatChannelData![channel], 0, 4096 * MemoryLayout<Float>.size) }
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            let count = CMSampleBufferGetNumSamples(sample)
            let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard seconds.isFinite, count > 0 else { continue }
            let position = AVAudioFramePosition((seconds * 48000).rounded())
            while file.framePosition < position {
                try Task.checkCancellation()
                silence.frameLength = AVAudioFrameCount(min(4096, position - file.framePosition)); try file.write(from: silence)
            }
            let skip = Int(max(0, file.framePosition - position))
            guard skip < count, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count - skip)) else { continue }
            buffer.frameLength = AVAudioFrameCount(count - skip)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: Int32(skip), frameCount: Int32(count - skip), into: buffer.mutableAudioBufferList)
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            try file.write(from: buffer)
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        let end = AVAudioFramePosition((max(0, duration) * 48000).rounded())
        while file.framePosition < end {
            try Task.checkCancellation()
            silence.frameLength = AVAudioFrameCount(min(4096, end - file.framePosition))
            try file.write(from: silence)
        }
    }

}
