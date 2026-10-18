import AVFoundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published var error: String?
    private var recorder: AVAudioRecorder?

    func toggle() {
        if recording { recorder?.stop(); recorder = nil; recording = false; return }
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                error = "Autorisez le microphone dans Réglages Système > Confidentialité et sécurité > Microphone."; return
            }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.nameFieldStringValue = "Enregistrement.wav"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false])
                guard recorder.record() else { throw NSError(domain: "Cappella", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossible de démarrer l'enregistrement."]) }
                self.recorder = recorder; recording = true
            } catch { self.error = error.localizedDescription }
        }
    }
    deinit { recorder?.stop() }
}
