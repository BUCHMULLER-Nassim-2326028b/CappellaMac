import Foundation
import CappellaCore
import CWindowsInterop

/// Reverse preparation only. Normal playback never calls this decoder or cache.
final class WindowsAudioPreparation {
    let directory: URL
    private(set) var reversedVersions: [URL] = []
    private(set) var durations: [Double] = []
    private func use(_ cache: PCMPlaybackCache) {
        reversedVersions = cache.reverse; durations = cache.durations
    }
    private init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func prepare(_ source: URL) throws -> WindowsAudioPreparation {
        let result = try WindowsAudioPreparation()
        if ["aif", "aiff", "aifc", "wav"].contains(source.pathExtension.lowercased()) {
            do {
                result.use(try PCMPlaybackCache.prepare([source]))
                return result
            } catch is CancellationError { throw CancellationError() }
            catch { /* A compressed source needs the native decoder. */ }
        }
        var decodedFiles: [URL] = []
        defer { for file in decodedFiles { try? FileManager.default.removeItem(at: file) } }
        result.use(try PCMPlaybackCache.prepare([source], decode: {
            var files: [URL] = [], streams: Int32 = 0, ordinal: Int32 = 0
            repeat {
                try Task.checkCancellation()
                let url = result.directory.appendingPathComponent("decoded-\(ordinal).wav")
                var duration = 0.0
                let status = (Array(source.path.utf16) + [0]).withUnsafeBufferPointer { input in
                    (Array(url.path.utf16) + [0]).withUnsafeBufferPointer { output in
                        cappella_decode_audio(input.baseAddress, output.baseAddress, ordinal, &streams, &duration, { Task.isCancelled ? 1 : 0 })
                    }
                }
                try Task.checkCancellation()
                guard status >= 0 else {
                    throw ProjectError.invalid("Décodage audio impossible (\(String(UInt32(bitPattern: status), radix: 16))).")
                }
                if status == 0 { files.append(url); decodedFiles.append(url) }
                ordinal += 1
            } while ordinal < streams
            return files
        }))
        return result
    }
}
