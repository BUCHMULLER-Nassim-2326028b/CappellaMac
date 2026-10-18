import AVFoundation

enum ShotDetector {
    /// Decode in presentation order and compare a small RGB sampling grid.
    /// No playback, screen capture or external codec process is involved.
    static func detect(url: URL, fps: Int, threshold: Double, progress: @escaping @Sendable (Double) -> Void) async throws -> [Int] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Cappella", code: 1, userInfo: [NSLocalizedDescriptionKey: "Le fichier ne contient pas de piste vidéo."])
        }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw NSError(domain: "Cappella", code: 2) }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "Cappella", code: 3) }
        var previous: [UInt8] = []
        var shots: [Int] = []
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(image, .readOnly)
            var colors: [UInt8] = []
            if let base = CVPixelBufferGetBaseAddress(image) {
                let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image), stride = CVPixelBufferGetBytesPerRow(image)
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                colors.reserveCapacity(32 * 18 * 3)
                for y in 0..<18 {
                    for x in 0..<32 {
                        let offset = min(height - 1, y * height / 18) * stride + min(width - 1, x * width / 32) * 4
                        colors.append(bytes[offset]); colors.append(bytes[offset + 1]); colors.append(bytes[offset + 2])
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if !colors.isEmpty, previous.count == colors.count {
                var difference = 0
                for i in colors.indices { difference += abs(Int(colors[i]) - Int(previous[i])) }
                if Double(difference) / Double(colors.count * 255) >= threshold {
                    let frame = max(0, Int((time * Double(fps)).rounded()))
                    if shots.last != frame { shots.append(frame) }
                }
            }
            previous = colors; count += 1
            if count % 50 == 0, duration > 0 { progress(min(1, time / duration)) }
        }
        if reader.status == .failed { throw reader.error ?? NSError(domain: "Cappella", code: 4) }
        progress(1); return shots
    }
}
