import Foundation

/// Converts uncompressed AIFF to WAV; four channels become VO/VI stereo pairs.
/// Source files are only read. Finished conversions are reused across launches.
enum WindowsAudioPreparation {
    static func prepare(_ url: URL) throws -> [URL] {
        guard ["aif", "aiff", "aifc"].contains(url.pathExtension.lowercased()) else { return [url] }
        func invalid(_ message: String) -> NSError {
            NSError(domain: "CappellaAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        func read(_ count: Int) throws -> [UInt8] {
            let bytes = Array(try input.read(upToCount: count) ?? Data())
            guard bytes.count == count else { throw invalid("Fichier AIFF tronque.") }
            return bytes
        }
        func be(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt64 {
            bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
        }
        let header = try read(12)
        let format = String(bytes: header[8..<12], encoding: .ascii)
        guard String(bytes: header[0..<4], encoding: .ascii) == "FORM", format == "AIFF" || format == "AIFC" else {
            throw invalid("Format AIFF non reconnu.")
        }
        let fileSize = try input.seekToEnd()
        try input.seek(toOffset: 12)
        var channels = 0, bits = 0, rate = 0, frames: UInt64 = 0
        var audioOffset: UInt64 = 0, audioBytes: UInt64 = 0
        var littleEndian = false
        while try input.offset() + 8 <= fileSize {
            let chunk = try read(8), size = be(chunk, 4, 4)
            let start = try input.offset()
            guard size <= fileSize - start else { throw invalid("Taille de bloc AIFF invalide.") }
            let tag = String(bytes: chunk[0..<4], encoding: .ascii)
            if tag == "COMM" {
                guard size >= (format == "AIFC" ? 22 : 18) else { throw invalid("Bloc COMM AIFF invalide.") }
                let data = try read(format == "AIFC" ? 22 : 18)
                channels = Int(be(data, 0, 2)); frames = be(data, 2, 4); bits = Int(be(data, 6, 2))
                let exponent = Int(be(data, 8, 2))
                let frequency = Double(be(data, 10, 8)) * pow(2.0, Double(exponent - 16383 - 63))
                guard exponent < 32768, frequency.isFinite, frequency >= 1, frequency <= 384000 else { throw invalid("Cadence AIFF invalide.") }
                rate = Int(frequency.rounded())
                if format == "AIFC" {
                    let codec = String(bytes: data[18..<22], encoding: .ascii)
                    guard codec == "NONE" || codec == "twos" || codec == "sowt" else { throw invalid("Compression AIFF non prise en charge : " + (codec ?? "?") + ".") }
                    littleEndian = codec == "sowt"
                }
            } else if tag == "SSND" {
                guard size >= 8 else { throw invalid("Bloc SSND AIFF invalide.") }
                let data = try read(8), offset = be(data, 0, 4)
                guard offset <= size - 8 else { throw invalid("Decalage AIFF invalide.") }
                audioOffset = start + 8 + offset; audioBytes = size - 8 - offset
            }
            try input.seek(toOffset: start + size + size % 2)
        }
        guard [1, 2, 4].contains(channels), [8, 16, 24, 32].contains(bits), rate > 0, audioOffset > 0, frames > 0 else {
            throw invalid("Audio AIFF attendu : PCM 8/16/24/32 bits, mono, stereo ou quatre canaux.")
        }
        let sampleBytes = bits / 8, outputChannels = min(channels, 2)
        let frameBytes = channels * sampleBytes
        guard frames <= audioBytes / UInt64(frameBytes) else { throw invalid("Donnees audio AIFF incompletes.") }
        let outputBytes = frames * UInt64(outputChannels * sampleBytes)
        guard outputBytes <= UInt64(UInt32.max) - 36 else { throw invalid("Audio trop volumineux pour WAV.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = url.standardizedFileURL.path + "|\(fileSize)|\(stamp)|pcm-v1"
        let hash = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CappellaAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let outputs = (0..<(channels == 4 ? 2 : 1)).map { folder.appendingPathComponent("\(hash)-\($0).wav") }
        if outputs.allSatisfy({ ((try? FileManager.default.attributesOfItem(atPath: $0.path)[.size]) as? NSNumber)?.uint64Value == outputBytes + 44 + outputBytes % 2 }) { return outputs }
        let temporary = outputs.map { $0.appendingPathExtension(UUID().uuidString + ".partial") }
        var handles: [FileHandle] = []
        defer {
            for handle in handles { try? handle.close() }
            for file in temporary { try? FileManager.default.removeItem(at: file) }
        }
        var wav = Data("RIFF".utf8)
        func append(_ value: UInt32, bytes: Int) {
            for index in 0..<bytes { wav.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
        }
        append(UInt32(outputBytes + 36 + outputBytes % 2), bytes: 4); wav.append(Data("WAVEfmt ".utf8))
        append(16, bytes: 4); append(1, bytes: 2); append(UInt32(outputChannels), bytes: 2)
        append(UInt32(rate), bytes: 4); append(UInt32(rate * outputChannels * sampleBytes), bytes: 4)
        append(UInt32(outputChannels * sampleBytes), bytes: 2); append(UInt32(bits), bytes: 2)
        wav.append(Data("data".utf8)); append(UInt32(outputBytes), bytes: 4)
        for file in temporary {
            try wav.write(to: file)
            let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); handles.append(handle)
        }
        try input.seek(toOffset: audioOffset)
        var remaining = frames
        while remaining > 0 {
            let count = Int(min(remaining, 32768)), data = try read(count * frameBytes)
            for pair in handles.indices {
                var pcm = [UInt8](repeating: 0, count: count * outputChannels * sampleBytes)
                for frame in 0..<count {
                    for channel in 0..<outputChannels {
                        let source = frame * frameBytes + (pair * 2 + channel) * sampleBytes
                        let target = (frame * outputChannels + channel) * sampleBytes
                        for byte in 0..<sampleBytes {
                            pcm[target + byte] = data[source + (littleEndian ? byte : sampleBytes - 1 - byte)]
                        }
                        if bits == 8 { pcm[target] ^= 0x80 }
                    }
                }
                try handles[pair].write(contentsOf: Data(pcm))
            }
            remaining -= UInt64(count)
        }
        for handle in handles {
            if outputBytes % 2 != 0 { try handle.write(contentsOf: Data([0])) }
            try handle.close()
        }
        handles.removeAll()
        for (file, output) in zip(temporary, outputs) {
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try FileManager.default.moveItem(at: file, to: output)
        }
        return outputs
    }
}