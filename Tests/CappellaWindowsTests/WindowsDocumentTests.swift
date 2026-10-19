import XCTest
import Foundation
import CappellaCore
@testable import CappellaWindows

final class WindowsDocumentTests: XCTestCase {
    func testActivationParsesQuotedUnicodePathsWithoutTreatingThemAsOptions() {
        let files = WindowsActivation.files(in: #""C:\Program Files\Cappella\Cappella.exe" "D:\Mes projets\Élliott #107.detx""#)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, "Élliott #107.detx")
    }
    private func example() -> Project {
        var project = Project()
        let role = Role(name: "Élliott")
        project.roles = [role]
        project.cues = [Cue(roleID: role.id, start: 100, end: 200, text: "Merci maman.")]
        project.loops = [Marker(frame: 250, label: "1")]
        project.shots = [Marker(frame: 225, label: "plan")]
        return project
    }
    func testEditingCancellationRestoresPhraseWithoutSeeking() throws {
        let document = WindowsDocument()
        document.replace(with: example(), url: nil)
        document.frame = 150
        let original = document.project.cues[0]
        document.beginEditing(original, at: 160)
        try document.setText("Merci é🙂 maman.", caret: 7)
        XCTAssertEqual(document.frame, 150)
        XCTAssertTrue(document.dirty)
        try document.project.validate()
        document.cancelEditing()
        XCTAssertEqual(document.project.cues[0], original)
        XCTAssertFalse(document.dirty)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
    }
    func testNavigationIncludesShotsAndLoopsAndDoesNotRepeatTargets() {
        let document = WindowsDocument()
        document.replace(with: example(), url: nil)
        document.frame = 200
        XCTAssertEqual(document.navigate("sign", 1), 225)
        XCTAssertEqual(document.navigate("sign", 1), 250)
        XCTAssertNil(document.navigate("sign", 1))
        XCTAssertEqual(document.navigate("sign", -1), 225)
    }
    func testTrackMoveRejectsCollisionsAndUndoRestoresTrack() throws {
        let document = WindowsDocument()
        var project = example()
        var collision = project.cues[0]; collision.id = UUID(); collision.track = 1
        project.cues.append(collision)
        document.replace(with: project, url: nil)
        document.selection = project.cues[0].id
        XCTAssertThrowsError(try document.moveTrack(1))
        try document.moveTrack(2)
        XCTAssertEqual(document.selectedCue?.track, 2)
        document.undo()
        XCTAssertEqual(document.selectedCue?.track, 0)
    }
    func testSaveCopyPreservesSourceAndDirtyStateAndRoundTripsDetX() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.detx")
        let copy = directory.appendingPathComponent("copie.detx")
        let document = WindowsDocument()
        document.replace(with: example(), url: nil)
        try document.save(to: source)
        let original = try Data(contentsOf: source)
        document.selection = document.project.cues[0].id
        try document.setText("Une nouvelle réplique.", caret: 0)
        try document.save(to: copy, copy: true)
        XCTAssertTrue(document.dirty)
        XCTAssertEqual(document.url, source)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try document.read(copy).cues[0].text, "Une nouvelle réplique.")
        document.frame = 170
        try document.save(to: source)
        XCTAssertFalse(document.dirty)
        XCTAssertEqual(try document.read(source).lastPositionFrame, 170)
    }
    func testCancelledNewPhraseIsRemovedFromHistory() throws {
        let document = WindowsDocument()
        document.replace(with: example(), url: nil)
        document.frame = 300
        try document.createPhrase(role: document.project.roles[0].id)
        try document.setText("Texte à abandonner", caret: 18)
        document.cancelEditing()
        XCTAssertEqual(document.project.cues.count, 1)
        XCTAssertFalse(document.dirty)
        XCTAssertFalse(document.canUndo)
    }
    func testAutomaticSaveCanBeDisabledAndDoesNotCleanOrOverwriteDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.detx")
        let backups = directory.appendingPathComponent("recovery")
        let document = WindowsDocument()
        document.replace(with: example(), url: nil)
        try document.save(to: source)
        let before = try Data(contentsOf: source)
        document.selection = document.project.cues[0].id
        try document.setText("Texte récupérable", caret: 16)
        var preferences = ApplicationPreferences()
        preferences.automaticSave = false
        let now = Date().addingTimeInterval(1_000)
        try document.autoSave(at: now, using: preferences, in: backups)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        preferences.automaticSave = true; preferences.saveInterval = 1
        try document.autoSave(at: now.addingTimeInterval(61), using: preferences, in: backups)
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try document.read(recovery).cues[0].text, "Texte récupérable")
        XCTAssertTrue(document.dirty)
        XCTAssertEqual(try Data(contentsOf: source), before)
    }
}
