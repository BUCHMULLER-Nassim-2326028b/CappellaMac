import Foundation
import CappellaCore
import UWP
import WindowsFoundation

/// Supplies a few milliseconds of PCM on demand. Opening/seeking never
/// converts the entire source, including AIFF and four-channel VO/VI files.
final class WindowsPCMSource {
    let source: MediaStreamSource
    private let reader: PCMChannelPreparation.Stream
    private let channels: [Int]
    private let lock = NSLock()
    private var frame = 0
    private var discontinuous = true

    init(reader: PCMChannelPreparation.Stream, channels: [Int]) throws {
        self.reader = reader; self.channels = channels
        let encoding = try AudioEncodingProperties.createPcm(UInt32(reader.sampleRate), UInt32(channels.count), UInt32(reader.bitsPerSample))
        source = MediaStreamSource(AudioStreamDescriptor(encoding))
        source.canSeek = true
        source.duration = TimeSpan(duration: Int64(reader.frameCount) * 10_000_000 / Int64(reader.sampleRate))
        source.bufferTime = TimeSpan(duration: 0)
        source.maxSupportedPlaybackRate = 10
        source.starting.addHandler { [weak self] _, args in
            guard let self, let request = args?.request else { return }
            lock.lock(); defer { lock.unlock() }
            if let target = request.startPosition {
                frame = min(reader.frameCount, max(0, Int(Double(target.duration) * Double(reader.sampleRate) / 10_000_000)))
            }
            discontinuous = true
            try? request.setActualStartPosition(TimeSpan(duration: Int64(frame) * 10_000_000 / Int64(reader.sampleRate)))
        }
        source.sampleRequested.addHandler { [weak self] _, args in
            guard let self, let request = args?.request else { return }
            lock.lock(); defer { lock.unlock() }
            do {
                let count = min(2048, reader.frameCount - frame)
                guard count > 0 else { request.sample = nil; return }
                let data = try reader.read(frame: frame, count: count, channels: channels)
                let buffer = Buffer(UInt32(data.count))
                guard let bytes = try buffer.buffer else { throw CocoaError(.fileReadUnknown) }
                data.withUnsafeBytes { raw in
                    UnsafeMutableRawPointer(bytes).copyMemory(from: raw.baseAddress!, byteCount: data.count)
                }
                buffer.length = UInt32(data.count)
                let start = Int64(frame) * 10_000_000 / Int64(reader.sampleRate)
                let end = Int64(frame + count) * 10_000_000 / Int64(reader.sampleRate)
                guard let sample = try MediaStreamSample.createFromBuffer(buffer, TimeSpan(duration: start)) else {
                    throw CocoaError(.fileReadUnknown)
                }
                sample.duration = TimeSpan(duration: end - start)
                sample.discontinuous = discontinuous
                request.sample = sample
                frame += count; discontinuous = false
            } catch {
                try? source.notifyError(.other)
            }
        }
    }
    func playbackItem() throws -> MediaPlaybackItem {
        MediaPlaybackItem(try MediaSource.createFromMediaStreamSource(source))
    }
}