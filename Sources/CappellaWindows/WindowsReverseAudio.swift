import Foundation
import CWindowsInterop

/// Disposable, per-project PCM cache. Decoding runs outside the UI thread.
final class WindowsReverseAudio {
    let directory: URL
    private(set) var files: [URL] = []
    private(set) var durations: [Double] = []

    private init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-reverse-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func prepare(sources: [URL]) throws -> WindowsReverseAudio {
        let result = try WindowsReverseAudio()
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            let first = result.directory.appendingPathComponent("audio-\(index).wav")
            let second = result.directory.appendingPathComponent("vi-\(index).wav")
            var streams: Int32 = 0, paired: Int32 = 0
            var duration = 0.0
            func decode(_ ordinal: Int32, _ vo: URL, _ vi: URL) throws -> Bool {
                let status = (Array(source.path.utf16) + [0]).withUnsafeBufferPointer { input in
                    (Array(vo.path.utf16) + [0]).withUnsafeBufferPointer { output in
                        (Array(vi.path.utf16) + [0]).withUnsafeBufferPointer { alternate in
                            cappella_reverse_audio(input.baseAddress, output.baseAddress, alternate.baseAddress,
                                ordinal, &streams, &paired, &duration, { Task.isCancelled ? 1 : 0 })
                        }
                    }
                }
                try Task.checkCancellation()
                guard status >= 0 else {
                    throw NSError(domain: "CappellaReverseAudio", code: Int(status),
                        userInfo: [NSLocalizedDescriptionKey: "Préparation du son inversé impossible (\(String(UInt32(bitPattern: status), radix: 16)))."])
                }
                return status == 0
            }
            guard try decode(0, first, second) else { continue }
            result.files.append(first); result.durations.append(duration)
            if sources.count == 1 {
                if paired != 0 {
                    result.files.append(second); result.durations.append(duration)
                } else if streams >= 2 {
                    let unused = result.directory.appendingPathComponent("unused.wav")
                    if try decode(1, second, unused) {
                        result.files.append(second); result.durations.append(duration)
                    }
                }
            }
        }
        return result
    }
}
