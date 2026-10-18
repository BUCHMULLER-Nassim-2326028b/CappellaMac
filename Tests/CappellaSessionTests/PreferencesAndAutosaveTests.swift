import XCTest
import Foundation
import CappellaCore
@testable import CappellaSession

final class PreferencesAndAutosaveTests: XCTestCase {
    func testPreferencesPersistDisableAutomaticSaveAndLightDarkThemes() throws {
        let name = "Cappella-preferences-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(ApplicationPreferences.load(from: defaults).automaticSave)
        var value = ApplicationPreferences()
        value.automaticSave = false; value.saveInterval = 2; value.appearance = "dark"
        value.prefixCopies = false; value.checkUpdates = true; value.closeReactions = true
        value.showControlAtLaunch = true; value.videoOffsetMilliseconds = -150
        value.fontName = "Arial"; value.fontSize = 32; value.pixelsPerSecond = 180; value.bandHeight = 200
        value.showGrid = false; value.showDetection = false
        value.save(to: defaults)
        XCTAssertEqual(ApplicationPreferences.load(from: defaults), value)
        value.appearance = "light"; value.save(to: defaults)
        XCTAssertEqual(ApplicationPreferences.load(from: defaults).appearance, "light")
        XCTAssertEqual(value.copyName(for: "Épisode.detx"), "Épisode.detx")
        value.prefixCopies = true
        XCTAssertEqual(value.copyName(for: "Épisode.detx"), "Copie de Épisode.detx")
        XCTAssertEqual(value.copyName(for: "Copie de Épisode.detx"), "Copie de Épisode.detx")
    }

    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-autosave-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }
    @MainActor private func session() -> ProjectSession {
        let value = ProjectSession()
        value.chooseReplacement = { .discard }; value.recordRecent = { _ in }; value.reportFailure = { _ in }
        return value
    }
    @MainActor func testAutomaticSaveRespectsDisabledStateAndInterval() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let value = session(); value.project.author = "Travail en cours"
        var settings = ApplicationPreferences(); settings.automaticSave = false; settings.saveInterval = 2
        let now = Date().addingTimeInterval(3600)
        XCTAssertNil(value.attemptAutomaticSave(at: now, preferences: settings, in: dir))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
        settings.automaticSave = true
        XCTAssertNil(value.attemptAutomaticSave(at: now.addingTimeInterval(119), preferences: settings, in: dir))
        let url = try XCTUnwrap(value.attemptAutomaticSave(at: now.addingTimeInterval(120), preferences: settings, in: dir))
        XCTAssertEqual(try Project.decode(Data(contentsOf: url)).author, "Travail en cours")
        XCTAssertTrue(value.isModified); XCTAssertNil(value.fileURL)
        XCTAssertNil(value.attemptAutomaticSave(at: now.addingTimeInterval(240), preferences: settings, in: dir))
        value.project.author = "Nouvelle modification"; settings.automaticSave = false
        XCTAssertNil(value.attemptAutomaticSave(at: now.addingTimeInterval(360), preferences: settings, in: dir))
        XCTAssertEqual(try Project.decode(Data(contentsOf: url)).author, "Travail en cours")
    }
    @MainActor func testRecoveryKeepsSourceFileAndRequiresSavingAsANewDocument() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var original = Project(); original.author = "Original"
        let source = dir.appendingPathComponent("Original.cappellaproject")
        let sourceData = try original.encode(); try sourceData.write(to: source)
        let value = session(); XCTAssertTrue(value.open(source))
        value.project.author = "À récupérer"
        let backup = try XCTUnwrap(value.writeAutomaticBackup(in: dir.appendingPathComponent("Autosaves")))
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
        XCTAssertEqual(value.fileURL, source); XCTAssertTrue(value.isModified)
        let recovered = session(); XCTAssertTrue(recovered.open(backup, asRecovery: true))
        XCTAssertEqual(recovered.project.author, "À récupérer"); XCTAssertNil(recovered.fileURL); XCTAssertTrue(recovered.isModified)
        let destination = dir.appendingPathComponent("Récupéré.cappellaproject")
        recovered.chooseSaveDestination = { destination }
        XCTAssertTrue(recovered.save()); XCTAssertFalse(recovered.isModified)
        XCTAssertEqual(try Project.decode(Data(contentsOf: destination)).author, "À récupérer")
        XCTAssertEqual(try Data(contentsOf: source), sourceData)
    }
    @MainActor func testAutomaticSaveFailurePreservesDirtyStateAndCanBeRetried() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let badFolder = dir.appendingPathComponent("not-a-directory"); try Data().write(to: badFolder)
        let value = session(); value.project.author = "À conserver"
        XCTAssertNil(value.writeAutomaticBackup(in: badFolder))
        XCTAssertNotNil(value.automaticSaveError); XCTAssertTrue(value.isModified)
        XCTAssertNotNil(value.writeAutomaticBackup(in: dir))
        XCTAssertNil(value.automaticSaveError); XCTAssertTrue(value.isModified)
    }
}
