import XCTest
@testable import CappellaCore

final class EditingRegressionTests: XCTestCase {
    private func cue() -> Cue {
        var cue = Cue(start: 100, end: 200, text: "Bonjour maman.")
        cue.signs = [SyncSign(frame: 100, textOffset: 0, kind: "in_open"),
                     SyncSign(frame: 150, textOffset: 8, kind: "mpb"),
                     SyncSign(frame: 200, textOffset: 14, kind: "out_open")]
        return cue
    }
    func testTypingBeforeAnAttachedWordKeepsItsSignOnTheWord() throws {
        var value = cue()
        value.editText("Bonjour chère maman.")
        XCTAssertEqual(value.signs?[1].textOffset, 8) // insertion exactly at anchor stays on its left edge
        value.editText("Oh ! Bonjour chère maman.")
        XCTAssertEqual(value.signs?[1].textOffset, 13)
        XCTAssertEqual(value.signs?.map(\.frame), [100, 150, 200])
        var project = Project(); let role = Role(name: "Maman"); project.roles = [role]; value.roleID = role.id; project.cues = [value]
        try project.validate()
        let restored = try DetX.read(DetX.write(project))
        XCTAssertEqual(restored.cues.first?.text, value.text)
        XCTAssertEqual(restored.cues.first?.signs?.map(\.textOffset), value.signs?.map(\.textOffset))
    }
    func testDeletingAcrossAnAnchorKeepsMonotonicOffsets() throws {
        var value = cue(); value.editText("Bon.")
        var project = Project(); project.cues = [value]
        try project.validate()
        XCTAssertEqual(value.signs?.last?.textOffset, 4)
        XCTAssertEqual(value.signs?.map(\.frame), [100, 150, 200])
    }
    func testEditingCombiningCharactersUsesDetXScalarOffsets() throws {
        var value = cue(); value.editText("É👋 Bonjour maman.")
        XCTAssertEqual(value.signs?[1].textOffset, 11)
        value.editText("E\u{301}👋 Bonjour maman.")
        XCTAssertEqual(value.signs?[1].textOffset, 12)
        var project = Project(); project.cues = [value]; try project.validate()
    }
    func testVOAndVISelectDisjointPairsAcrossContainerTracks() {
        // Two stereo tracks are four logical channels, just as a single 4-channel AIFF.
        let tracks = [["VO L", "VO R"], ["VI L", "VI R"]].flatMap { $0 }
        XCTAssertEqual(AudioRouting.selectedChannels(total: tracks.count, international: false).map { tracks[$0] }, ["VO L", "VO R"])
        XCTAssertEqual(AudioRouting.selectedChannels(total: tracks.count, international: true).map { tracks[$0] }, ["VI L", "VI R"])
        let mono = ["VO", "VI"]
        XCTAssertEqual(AudioRouting.selectedChannels(total: 2, international: true).map { mono[$0] }, ["VI"])
        XCTAssertEqual(AudioRouting.selectedChannels(total: 1, international: true), [])
    }
}
