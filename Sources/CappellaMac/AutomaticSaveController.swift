import Foundation
import CappellaSession

@MainActor
final class AutomaticSaveController {
    static let shared = AutomaticSaveController()
    private var timer: Timer?
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func tick() {
        _ = ProjectSession.shared.attemptAutomaticSave(preferences: ApplicationPreferences.load())
    }
}
