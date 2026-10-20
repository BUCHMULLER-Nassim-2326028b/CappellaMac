import Foundation

/// Container-independent channel routing after native decoding to linear PCM.
public enum PCMChannelPreparation {
    private struct Input {
        let file: FileHandle
        let channels: Int
        let bits: Int
        let rate: Int
        let format: Int
        let frames: Int
        let offset: UInt64
        var bigEndian = false
        var signedEightBit = false
        var stride: Int { channels * (bits / 8) }
    }
    private static func open(_ url: URL) throws -> Input {
        let file = try FileHandle(forReadingFrom: url)
        do {
            func read(_ count: Int) throws -> [UInt8] {
                let data = Array(try file.read(upToCount: count) ?? Data())
                guard data.count == count else { throw ProjectError.invalid("Fichier PCM tronqué.") }
                return data
            }
            func le(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int {
                var value = 0
                for index in 0..<count { value |= Int(bytes[start + index]) << (8 * index) }
                return value
            }
            let header = try read(12)
            if String(bytes: header[0..<4], encoding: .ascii) == "FORM" {
                return try openAIFF(file, header: header)
            }
            guard String(bytes: header[0..<4], encoding: .ascii) == "RIFF",
                  String(bytes: header[8..<12], encoding: .ascii) == "WAVE" else { throw ProjectError.invalid("Audio PCM WAV attendu.") }
            let length = try file.seekToEnd()
            var position: UInt64 = 12, description: [UInt8]?, dataOffset: UInt64?, dataSize = 0
            while position + 8 <= length {
                try file.seek(toOffset: position)
                let chunk = try read(8), size = le(chunk, 4, 4)
                guard UInt64(size) <= length - position - 8 else { throw ProjectError.invalid("Bloc WAV tronqué.") }
                let name = String(bytes: chunk[0..<4], encoding: .ascii)
                if name == "fmt " {
                    guard size >= 16, size <= 65536 else { throw ProjectError.invalid("Format PCM invalide.") }
                    description = try read(size)
                } else if name == "data" { dataOffset = position + 8; dataSize = size }
                position += 8 + UInt64(size) + UInt64(size % 2)
            }
            guard let fmt = description, let offset = dataOffset else { throw ProjectError.invalid("Données PCM absentes.") }
            var format = le(fmt, 0, 2)
            if format == 65534, fmt.count >= 40 {
                let tail: [UInt8] = [0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]
                guard Array(fmt[28..<40]) == tail else { throw ProjectError.invalid("Sous-format WAV non pris en charge.") }
                format = le(fmt, 24, 4)
            }
            let channels = le(fmt, 2, 2), rate = le(fmt, 4, 4), bits = le(fmt, 14, 2)
            guard (1...32).contains(channels), rate > 0,
                  (format == 1 && [8, 16, 24, 32].contains(bits)) || (format == 3 && [32, 64].contains(bits)),
                  le(fmt, 12, 2) == channels * (bits / 8),
                  dataSize % (channels * (bits / 8)) == 0 else { throw ProjectError.invalid("Format PCM non pris en charge.") }
            try file.seek(toOffset: offset)
            return Input(file: file, channels: channels, bits: bits, rate: rate, format: format,
                         frames: dataSize / (channels * (bits / 8)), offset: offset)
        } catch { try? file.close(); throw error }
    }

    private static func openAIFF(_ file: FileHandle, header: [UInt8]) throws -> Input {
        let kind = String(bytes: header[8..<12], encoding: .ascii)
        guard kind == "AIFF" || kind == "AIFC" else { throw ProjectError.invalid("Format AIFF invalide.") }
        func read(_ count: Int) throws -> [UInt8] {
            let bytes = Array(try file.read(upToCount: count) ?? Data())
            guard bytes.count == count else { throw ProjectError.invalid("Audio AIFF tronqué.") }
            return bytes
        }
        func be(_ bytes: [UInt8], _ start: Int, _ count: Int) -> UInt64 {
            bytes[start..<(start + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        let length = try file.seekToEnd()
        var position: UInt64 = 12, offset: UInt64 = 0, size: UInt64 = 0
        var channels = 0, bits = 0, rate = 0, frames = 0, littleEndian = false
        while position + 8 <= length {
            try file.seek(toOffset: position)
            let chunk = try read(8), count = be(chunk, 4, 4)
            guard count <= length - position - 8 else { throw ProjectError.invalid("Bloc AIFF tronqué.") }
            switch String(bytes: chunk[0..<4], encoding: .ascii) {
            case "COMM":
                let needed = kind == "AIFC" ? 22 : 18
                guard count >= UInt64(needed) else { throw ProjectError.invalid("Format AIFF incomplet.") }
                let data = try read(needed)
                channels = Int(be(data, 0, 2)); frames = Int(be(data, 2, 4)); bits = Int(be(data, 6, 2))
                let exponent = Int(be(data, 8, 2))
                let frequency = Double(be(data, 10, 8)) * pow(2, Double(exponent - 16383 - 63))
                guard exponent < 32768, frequency.isFinite, frequency >= 1, frequency <= 384000 else {
                    throw ProjectError.invalid("Cadence AIFF invalide.")
                }
                rate = Int(frequency.rounded())
                if kind == "AIFC" {
                    let codec = String(bytes: data[18..<22], encoding: .ascii)
                    guard codec == "NONE" || codec == "twos" || codec == "sowt" else { throw ProjectError.invalid("Compression AIFF non prise en charge.") }
                    littleEndian = codec == "sowt"
                }
            case "SSND":
                guard count >= 8 else { throw ProjectError.invalid("Bloc AIFF incomplet.") }
                let skip = be(try read(8), 0, 4)
                guard skip <= count - 8 else { throw ProjectError.invalid("Décalage AIFF invalide.") }
                offset = position + 16 + skip; size = count - 8 - skip
            default: break
            }
            position += 8 + count + count % 2
        }
        guard (1...32).contains(channels), [8, 16, 24, 32].contains(bits), rate > 0, offset > 0,
              UInt64(frames) <= size / UInt64(channels * (bits / 8)) else { throw ProjectError.invalid("Format PCM AIFF invalide.") }
        return Input(file: file, channels: channels, bits: bits, rate: rate, format: 1,
                     frames: frames, offset: offset, bigEndian: !littleEndian, signedEightBit: bits == 8)
    }
    /// Bounded reads for normal playback: no full-file conversion or cache.
    public final class Stream {
        private let input: Input
        private let lock = NSLock()
        public var channels: Int { input.channels }
        public var sampleRate: Int { input.rate }
        public var bitsPerSample: Int { input.format == 3 ? 32 : input.bits }
        public var frameCount: Int { input.frames }
        public init(_ source: URL) throws { input = try PCMChannelPreparation.open(source) }
        deinit { try? input.file.close() }
        public func read(frame: Int, count: Int, channels: [Int]) throws -> Data {
            lock.lock(); defer { lock.unlock() }
            guard frame >= 0, channels.allSatisfy({ (0..<input.channels).contains($0) }) else {
                throw ProjectError.invalid("Position ou canaux PCM invalides.")
            }
            let count = min(max(0, count), max(0, input.frames - frame))
            guard count > 0, !channels.isEmpty else { return Data() }
            try input.file.seek(toOffset: input.offset + UInt64(frame * input.stride))
            let data = try input.file.read(upToCount: count * input.stride) ?? Data()
            guard data.count == count * input.stride else { throw ProjectError.invalid("Données PCM incomplètes.") }
            let sampleBytes = bitsPerSample / 8
            var output = Data(count: count * channels.count * sampleBytes)
            output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                    for sampleFrame in 0..<count {
                        for (outputChannel, channel) in channels.enumerated() {
                            let offset = sampleFrame * input.stride + channel * (input.bits / 8)
                            let target = (sampleFrame * channels.count + outputChannel) * sampleBytes
                            if input.format == 3 {
                                var raw: UInt64 = 0
                                for byte in 0..<(input.bits / 8) { raw |= UInt64(source[offset + byte]) << (8 * byte) }
                                let floating = input.bits == 32 ? Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))) : Double(bitPattern: raw)
                                let value = Int32(max(-2147483648, min(2147483647, (floating.isFinite ? floating : 0) * 2147483648)))
                                destination.storeBytes(of: value.littleEndian, toByteOffset: target, as: Int32.self)
                            } else {
                                for byte in 0..<sampleBytes {
                                    let index = input.bigEndian ? sampleBytes - byte - 1 : byte
                                    destination[target + byte] = source[offset + index] ^ (input.signedEightBit ? 0x80 : 0)
                                }
                            }
                        }
                    }
                }
            }
            return output
        }
    }
    public static func duration(of source: URL) throws -> Double {
        let input = try open(source); defer { try? input.file.close() }
        return Double(input.frames) / Double(input.rate)
    }
    public static func prepare(_ sources: [URL], in directory: URL,
                               reverse: Bool = false, routeChannels: Bool = true,
                               minimumDuration: Double = 0) throws -> [URL] {
        guard !sources.isEmpty else { return [] }
        var inputs: [Input] = []
        defer { for input in inputs { try? input.file.close() } }
        for url in sources { inputs.append(try open(url)) }
        let first = inputs[0]
        guard inputs.allSatisfy({ $0.rate == first.rate && $0.bits == first.bits && $0.format == first.format }) else {
            throw ProjectError.invalid("Les flux audio doivent avoir la même cadence et le même format PCM.")
        }
        let total = inputs.reduce(0) { $0 + $1.channels }
        let routes = routeChannels ? AudioRouting.versions(total: total) : [Array(0..<total)]
        let frames = max(inputs.map(\.frames).max() ?? 0, Int((max(0, minimumDuration) * Double(first.rate)).rounded())), sampleBytes = first.bits / 8
        var channelMap: [(input: Int, channel: Int)] = []
        for (index, input) in inputs.enumerated() {
            for channel in 0..<input.channels { channelMap.append((index, channel)) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var outputs: [URL] = [], handles: [FileHandle] = []
        defer { for file in handles { try? file.close() } }
        for (index, channels) in routes.enumerated() {
            let bytes = UInt64(frames) * UInt64(channels.count * sampleBytes)
            let fact = first.format == 3 ? 12 : 0
            guard bytes + 36 + UInt64(fact) + bytes % 2 <= UInt64(UInt32.max) else { throw ProjectError.invalid("Audio trop volumineux pour WAV.") }
            var header = Data("RIFF".utf8)
            func append(_ value: Int, _ count: Int) {
                for byte in 0..<count { header.append(UInt8(truncatingIfNeeded: value >> (8 * byte))) }
            }
            append(Int(bytes) + 36 + fact + Int(bytes % 2), 4); header.append(Data("WAVEfmt ".utf8))
            append(16, 4); append(first.format, 2); append(channels.count, 2); append(first.rate, 4)
            append(first.rate * channels.count * sampleBytes, 4); append(channels.count * sampleBytes, 2); append(first.bits, 2)
            if fact > 0 { header.append(Data("fact".utf8)); append(4, 4); append(frames, 4) }
            header.append(Data("data".utf8)); append(Int(bytes), 4)
            let url = directory.appendingPathComponent(index == 0 ? "VO.wav" : "VI.wav")
            try header.write(to: url)
            let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
            handles.append(handle); outputs.append(url)
        }
        var position = 0
        while position < frames {
            try Task.checkCancellation()
            let count = min(8192, frames - position)
            let sourcePosition = reverse ? frames - position - count : position
            var buffers: [Data] = []
            for input in inputs {
                let amount = min(count, max(0, input.frames - sourcePosition)) * input.stride
                try input.file.seek(toOffset: input.offset + UInt64(min(sourcePosition, input.frames) * input.stride))
                let data = try input.file.read(upToCount: amount) ?? Data()
                guard data.count == amount else { throw ProjectError.invalid("Données PCM incomplètes.") }
                buffers.append(data)
            }
            for (version, channels) in routes.enumerated() {
                let stride = channels.count * sampleBytes
                var bytes = Data(repeating: first.bits == 8 ? 128 : 0, count: count * stride)
                bytes.withUnsafeMutableBytes { destination in
                    let target = destination.baseAddress!
                    for (targetChannel, sourceChannel) in channels.enumerated() {
                        let map = channelMap[sourceChannel], input = inputs[map.input]
                        buffers[map.input].withUnsafeBytes { source in
                            let available = min(count, max(0, input.frames - sourcePosition))
                            guard available > 0 else { return }
                            let data = source.baseAddress!
                            let contiguous = !input.bigEndian && !input.signedEightBit && channels.count == input.channels &&
                                channels.enumerated().allSatisfy { channelMap[$0.element].input == map.input && channelMap[$0.element].channel == $0.offset }
                            if contiguous {
                                guard targetChannel == 0 else { return }
                                if !reverse { target.copyMemory(from: data, byteCount: available * stride) }
                                else {
                                    for frame in 0..<available {
                                        target.advanced(by: (count - frame - 1) * stride).copyMemory(from: data.advanced(by: frame * stride), byteCount: stride)
                                    }
                                }
                                return
                            }
                            for frame in 0..<available {
                                let outputFrame = reverse ? count - frame - 1 : frame
                                let src = data.advanced(by: frame * input.stride + map.channel * sampleBytes)
                                let dst = target.advanced(by: outputFrame * stride + targetChannel * sampleBytes)
                                switch sampleBytes {
                                case 1: dst.storeBytes(of: src.load(as: UInt8.self) ^ (input.signedEightBit ? 0x80 : 0), as: UInt8.self)
                                case 2:
                                    let value = src.loadUnaligned(as: UInt16.self)
                                    dst.storeBytes(of: input.bigEndian ? value.byteSwapped : value, as: UInt16.self)
                                case 4:
                                    let value = src.loadUnaligned(as: UInt32.self)
                                    dst.storeBytes(of: input.bigEndian ? value.byteSwapped : value, as: UInt32.self)
                                case 8:
                                    let value = src.loadUnaligned(as: UInt64.self)
                                    dst.storeBytes(of: input.bigEndian ? value.byteSwapped : value, as: UInt64.self)
                                default:
                                    for byte in 0..<sampleBytes {
                                        dst.storeBytes(of: src.load(fromByteOffset: input.bigEndian ? sampleBytes - byte - 1 : byte, as: UInt8.self), toByteOffset: byte, as: UInt8.self)
                                    }
                                }
                            }
                        }
                    }
                }
                try handles[version].write(contentsOf: bytes)
            }
            position += count
        }
        for (index, handle) in handles.enumerated() {
            if frames * routes[index].count * sampleBytes % 2 != 0 {
                try handle.write(contentsOf: Data([0]))
            }
        }
        return outputs
    }
}
