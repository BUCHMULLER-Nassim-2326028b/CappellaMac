import Foundation

/// Reversed PCM is reusable across openings. Forward playback never uses this cache.
public struct PCMPlaybackCache {
    public let reverse: [URL]
    public let durations: [Double]

    private struct Manifest: Codable {
        var files: [String]
        var durations: [Double]
    }

    public static func prepare(_ sources: [URL], routeChannels: Bool = true, identitySources: [URL]? = nil, minimumDuration: Double = 0, decode: (() throws -> [URL])? = nil) throws -> PCMPlaybackCache {
        var identity = "pcm-reverse-v3|\(routeChannels)|\(minimumDuration)"
        for source in identitySources ?? sources {
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            identity += "|\(source.standardizedFileURL.path)|\(attributes[.size] ?? 0)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        }
        let hash = identity.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CappellaPCM", isDirectory: true)
        let directory = root.appendingPathComponent(String(hash, radix: 16), isDirectory: true)
        func cached() -> PCMPlaybackCache? {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("complete.json")),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
            let reverse = manifest.files.map { directory.appendingPathComponent("reverse/" + $0) }
            guard manifest.durations.count == reverse.count,
                  reverse.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
            return PCMPlaybackCache(reverse: reverse, durations: manifest.durations)
        }
        if let result = cached() { return result }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let pcmSources = try decode?() ?? sources
        let files = try PCMChannelPreparation.prepare(pcmSources, in: staging.appendingPathComponent("reverse"), reverse: true,
            routeChannels: routeChannels, minimumDuration: minimumDuration)
        let manifest = Manifest(files: files.map(\.lastPathComponent), durations: try files.map { try PCMChannelPreparation.duration(of: $0) })
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("complete.json"), options: .atomic)
        try Task.checkCancellation()
        do { try FileManager.default.moveItem(at: staging, to: directory) }
        catch { if let result = cached() { return result }; throw error }
        guard let result = cached() else { throw ProjectError.invalid("Cache audio incomplet.") }
        return result
    }
}
