import XCTest
@testable import CappellaCore

final class SignDetachTests: XCTestCase {
    func testDetachRestoresInterpolationWithoutMovingOrRemovingTheSign() {
        var cue = Cue(start: 100, end: 200, text: "abcdefghij")
        cue.signs = [SyncSign(frame: 100, textOffset: 0, kind: "in_open"),
                     SyncSign(frame: 150, textOffset: 1, kind: "mpb"),
                     SyncSign(frame: 200, textOffset: 10, kind: "out_open")]
        let before = cue.anchors
        Timeline.detachSign(in: &cue, id: before[1].id)
        XCTAssertEqual(cue.anchors.map(\.frame), before.map(\.frame))
        XCTAssertEqual(cue.anchors.map(\.id), before.map(\.id))
        XCTAssertEqual(cue.anchors[1].textOffset, 5)
        Timeline.detachSign(in: &cue, id: before[0].id)
        XCTAssertEqual(cue.anchors.first?.textOffset, 0)
        XCTAssertEqual(cue.anchors.last?.textOffset, 10)
    }
}
