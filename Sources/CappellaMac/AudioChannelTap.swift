import AVFoundation
import MediaToolbox

/// Selects channels before AVPlayer's output mix. Each tap owns immutable routing;
/// changing VO/VI replaces the mix without seeking or changing the media clock.
enum AudioChannelTap {
    private final class State {
        let channels: Set<Int>
        var format = AudioStreamBasicDescription()
        init(_ channels: [Int]) { self.channels = Set(channels) }
    }

    static func make(channels: [Int]) throws -> MTAudioProcessingTap {
        let state = Unmanaged.passRetained(State(channels)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: state,
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().format = format.pointee
            },
            unprepare: nil,
            process: { tap, count, _, buffers, produced, flags in
                let status = MTAudioProcessingTapGetSourceAudio(tap, count, buffers, flags, nil, produced)
                guard status == noErr else { produced.pointee = 0; return }
                let state = Unmanaged<State>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let format = state.format
                let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                let strideChannels = interleaved ? max(1, Int(format.mChannelsPerFrame)) : 1
                let bytes = Int(format.mBytesPerFrame) / strideChannels
                guard bytes > 0 else { return }
                let list = UnsafeMutableAudioBufferListPointer(buffers)
                // A stereo source carries two mono versions: send the selected
                // version to both speakers. A packed four-channel source is
                // folded into its first stereo pair before the output mixer.
                let total = Int(format.mChannelsPerFrame)
                let monoVersion = total == 2 && state.channels.count == 1
                let secondPair = total == 4 && state.channels.count == 2 && state.channels.contains(2) && state.channels.contains(3)
                if monoVersion || secondPair {
                    func sample(_ channel: Int, _ frame: Int) -> UnsafeMutableRawPointer? {
                        var base = 0
                        for buffer in list {
                            let n = Int(buffer.mNumberChannels)
                            if channel < base + n, let data = buffer.mData {
                                let offset = (frame * n + channel - base) * bytes
                                return offset + bytes <= Int(buffer.mDataByteSize) ? data.advanced(by: offset) : nil
                            }
                            base += n
                        }
                        return nil
                    }
                    for frame in 0..<Int(produced.pointee) {
                        for output in 0..<2 {
                            let input = total == 2 ? (state.channels.first ?? 0) : output + 2
                            if let src = sample(input, frame), let dst = sample(output, frame), src != dst { memcpy(dst, src, bytes) }
                        }
                    }
                }
                var base = 0
                for buffer in list {
                    let channels = Int(buffer.mNumberChannels)
                    guard let data = buffer.mData else { base += channels; continue }
                    // Zero entire samples, supporting interleaved and planar PCM.
                    for channel in 0..<channels {
                        let audible = monoVersion || secondPair ? base + channel < 2 : state.channels.contains(base + channel)
                        if audible { continue }
                        for frame in 0..<Int(produced.pointee) {
                            let offset = (frame * channels + channel) * bytes
                            if offset + bytes <= Int(buffer.mDataByteSize) { memset(data.advanced(by: offset), 0, bytes) }
                        }
                    }
                    base += channels
                }
            })
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<State>.fromOpaque(state).release()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return tap.takeRetainedValue()
    }
}
