import XCTest
import AppKit
import Foundation
import CappellaCore
@testable import CappellaSession

final class ProjectSessionTests: XCTestCase {
    @MainActor private func session(_ title: String = "Projet courant") -> ProjectSession {
        var project = Project(); project.title = title
        let value = ProjectSession(project: project)
        value.chooseReplacement = { .cancel }
        value.chooseSaveDestination = { nil }
        value.reportFailure = { _ in }
        value.recordRecent = { _ in }
        return value
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cappella-session-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func write(_ title: String, in directory: URL) throws -> URL {
        var project = Project(); project.title = title
        let url = directory.appendingPathComponent(title + ".cappellaproject")
        try project.encode().write(to: url); return url
    }

    @MainActor func testCancelKeepsCurrentDocumentAndEditorIdentity() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let next = try write("Autre projet", in: dir)
        let value = session(); value.project.author = "Modifié"
        let original = value.project, identity = value.identity
        XCTAssertFalse(value.open(next)); XCTAssertFalse(value.newProject()); XCTAssertFalse(value.requestClose())
        XCTAssertEqual(value.project, original); XCTAssertEqual(value.identity, identity)
        XCTAssertNil(value.fileURL); XCTAssertTrue(value.isModified)
    }
    @MainActor func testDiscardReplacesDocumentInTheSameSession() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let next = try write("Autre projet", in: dir)
        let value = session(); value.project.author = "Modifié"; value.chooseReplacement = { .discard }
        let identity = value.identity
        XCTAssertTrue(value.open(next)); XCTAssertEqual(value.project.title, "Autre projet")
        XCTAssertEqual(value.fileURL, next); XCTAssertNotEqual(value.identity, identity); XCTAssertFalse(value.isModified)
    }
    @MainActor func testCancellingSaveAlsoCancelsOpeningAndQuitting() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let next = try write("Autre projet", in: dir)
        let value = session(); value.project.author = "À conserver"; value.chooseReplacement = { .save }
        let original = value.project
        XCTAssertFalse(value.open(next)); XCTAssertFalse(value.prepareToTerminate())
        XCTAssertEqual(value.project, original); XCTAssertTrue(value.isModified)
    }
    @MainActor func testSaveBeforeOpeningPreservesTheOldFile() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let next = try write("Autre projet", in: dir), saved = dir.appendingPathComponent("Sauvegarde.cappellaproject")
        let value = session(); value.project.author = "À conserver"; value.chooseReplacement = { .save }
        value.chooseSaveDestination = { saved }
        XCTAssertTrue(value.open(next))
        XCTAssertEqual(try Project.decode(Data(contentsOf: saved)).author, "À conserver")
        XCTAssertEqual(value.fileURL, next); XCTAssertFalse(value.isModified)
    }
    @MainActor func testReadFailureDoesNotPromptOrDiscardTheCurrentWork() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let broken = dir.appendingPathComponent("Cassé.detx"); try Data("pas du XML".utf8).write(to: broken)
        let value = session(); value.project.author = "À conserver"
        var confirmations = 0, failures = 0
        value.chooseReplacement = { confirmations += 1; return .discard }; value.reportFailure = { _ in failures += 1 }
        let identity = value.identity
        XCTAssertFalse(value.open(broken)); XCTAssertEqual(confirmations, 0); XCTAssertEqual(failures, 1)
        XCTAssertEqual(value.project.author, "À conserver"); XCTAssertEqual(value.identity, identity)
    }
    @MainActor func testWriteFailureKeepsTheDirtyProject() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let value = session(); value.project.author = "À conserver"; value.chooseReplacement = { .save }
        // A directory cannot be atomically replaced by the project's data.
        value.chooseSaveDestination = { dir }
        XCTAssertFalse(value.newProject()); XCTAssertEqual(value.project.author, "À conserver")
        XCTAssertTrue(value.isModified); XCTAssertNil(value.fileURL)
    }
    @MainActor func testSaveCopyDoesNotClearUnsavedChangesOrRenameCurrentProject() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let current = try write("Courant", in: dir), copy = dir.appendingPathComponent("Copie.cappellaproject")
        let value = session(); XCTAssertTrue(value.open(current)); value.project.author = "Modifié"
        value.chooseSaveDestination = { copy }
        XCTAssertTrue(value.save(copy: true)); XCTAssertEqual(value.fileURL, current); XCTAssertTrue(value.isModified)
        XCTAssertEqual(try Project.decode(Data(contentsOf: copy)).author, "Modifié")
        XCTAssertEqual(try Project.decode(Data(contentsOf: current)).author, "")
    }
    @MainActor func testOpeningAndCreatingProjectsReuseTheAttachedWindow() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("scene-owned-identifier")
        window.orderFront(nil); defer { window.close() }
        let value = session(); value.attach(window: window)
        let next = try write("Autre projet", in: dir)
        XCTAssertTrue(value.open(next)); XCTAssertTrue(value.window === window)
        XCTAssertEqual(value.visibleEditorWindowCount, 1)
        XCTAssertTrue(value.newProject()); XCTAssertTrue(value.window === window)
        XCTAssertEqual(value.visibleEditorWindowCount, 1)
        XCTAssertEqual(window.identifier?.rawValue, "scene-owned-identifier")
    }
    @MainActor func testLoadingOldNativeProjectDoesNotMarkNormalizedAnchorsAsEdits() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var project = Project(); project.cues = [Cue(start: 0, end: 25, text: "Bonjour")]
        let url = dir.appendingPathComponent("Ancien.cappellaproject"); try project.encode().write(to: url)
        let value = session(); XCTAssertTrue(value.open(url)); XCTAssertNotNil(value.project.cues[0].signs)
        XCTAssertFalse(value.isModified)
    }
}
