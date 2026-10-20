import Foundation

/// Reversal is already produced alongside forward PCM: installing players must
/// never launch a second full-media conversion when the direction changes.
final class WindowsReverseAudio {
    let files: [URL]
    let durations: [Double]
    init(files: [URL], durations: [Double]) {
        self.files = files; self.durations = durations
    }
}