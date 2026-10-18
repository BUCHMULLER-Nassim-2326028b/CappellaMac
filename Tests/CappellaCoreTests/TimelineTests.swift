import XCTest
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import CappellaCore

final class TimelineTests: XCTestCase {
    private func example() -> Project {
        var project = Project()
        let role = Role(name: "Élliott")
        project.roles = [role]
        var cue = Cue(roleID: role.id, start: 100, end: 200, text: "Merci maman.")
        cue.signs = [SyncSign(frame: 100, textOffset: 0, kind: "in_open"),
                     SyncSign(frame: 140, textOffset: 6, kind: "mpb"),
                     SyncSign(frame: 200, textOffset: 12, kind: "out_open")]
        project.cues = [cue]
        return project
    }

    func testIntermediateSignsRoundTripWithoutFlattening() throws {
        let project = example()
        let data = try DetX.write(project)
        let xml = try XMLDocument(data: data)
        XCTAssertEqual(try xml.nodes(forXPath: "/detx/body/line/lipsync").count, 3)
        XCTAssertEqual(try xml.nodes(forXPath: "/detx/body/line/text").map(\.stringValue), ["Merci ", "maman."])
        let result = try DetX.read(data)
        XCTAssertEqual(result.cues[0].text, "Merci maman.")
        XCTAssertEqual(result.cues[0].signs?.map(\.frame), [100, 140, 200])
        XCTAssertEqual(result.cues[0].signs?.map(\.textOffset), [0, 6, 12])
        XCTAssertEqual(result.cues[0].signs?.map(\.kind), ["in_open", "mpb", "out_open"])
    }

    func testTextSegmentsAndInterpolation() {
        let cue = example().cues[0]
        XCTAssertEqual(Timeline.segments(cue), [TimedText(start: 100, end: 140, text: "Merci "), TimedText(start: 140, end: 200, text: "maman.")])
        XCTAssertEqual(Timeline.textOffset(in: cue, at: 120), 3)
        XCTAssertEqual(Timeline.textOffset(in: cue, at: 170), 9)
        XCTAssertEqual(Timeline.textOffset(in: cue, at: 1), 0)
        XCTAssertEqual(Timeline.textOffset(in: cue, at: 500), 12)
    }

    func testEditingTextAndBoundsKeepsAnchorsValid() throws {
        var project = example()
        project.cues[0].replaceText("Merci mon ami !")
        try project.cues[0].setBounds(start: 200, end: 400)
        try project.validate()
        XCTAssertEqual(project.cues[0].signs?.map(\.frame), [200, 280, 400])
        XCTAssertEqual(project.cues[0].signs?.last?.textOffset, project.cues[0].text.count)
        let result = try DetX.read(DetX.write(project))
        XCTAssertEqual(result.cues[0].text, project.cues[0].text)
    }

    func testSignInsertionAndClamping() throws {
        var cue = example().cues[0]
        try Timeline.addSign(to: &cue, kind: "fvr", frame: 160, textOffset: 8)
        XCTAssertEqual(cue.signs?.count, 4)
        let sign = try XCTUnwrap(cue.signs?.first { $0.kind == "fvr" })
        Timeline.moveSign(in: &cue, id: sign.id, to: 10)
        XCTAssertEqual(cue.signs?.first { $0.id == sign.id }?.frame, 140)
        XCTAssertThrowsError(try Timeline.addSign(to: &cue, kind: "mpb", frame: 150, textOffset: 1))
        XCTAssertThrowsError(try Timeline.addSign(to: &cue, kind: "mpb", frame: 200, textOffset: 12))
    }

    func testShiftIsAtomicAndMovesAllSignsAndMarkers() throws {
        var project = example()
        project.mediaStartFrame = 50
        project.loops = [Marker(frame: 60, label: "1")]
        project.shots = [Marker(frame: 80, label: "1")]
        project.positions = [Marker(frame: 120, label: "Repère")]
        try project.shift(by: 25, includingMediaOrigin: true)
        XCTAssertEqual(project.mediaStartFrame, 75)
        XCTAssertEqual(project.cues[0].signs?.map(\.frame), [125, 165, 225])
        XCTAssertEqual(project.loops[0].frame, 85)
        XCTAssertEqual(project.shots[0].frame, 105)
        XCTAssertEqual(project.positions?[0].frame, 145)
        let before = project
        XCTAssertThrowsError(try project.shift(by: -1000))
        XCTAssertEqual(project, before)
        XCTAssertThrowsError(try project.shift(by: Int.min))
        XCTAssertEqual(project, before)
    }

    func testNewDetXMetadataPortraitsVoiceAndBookmarks() throws {
        var project = example()
        project.metadata = ["title2": "Titre français", "production.actors": "A & B", "episode.number": "07", "notes": "À garder"]
        project.roles[0].descriptionText = "Personnage"
        project.roles[0].imageData = Data([1, 2, 3])
        project.cues[0].voice = "off"
        project.loops = [Marker(frame: 90, label: "1")]
        project.positions = [Marker(frame: 150, label: "À reprendre")]
        let result = try DetX.read(DetX.write(project))
        XCTAssertEqual(result.metadata?["production.actors"], "A & B")
        XCTAssertEqual(result.metadata?["notes"], "À garder")
        XCTAssertEqual(result.roles[0].imageData, Data([1, 2, 3]))
        XCTAssertEqual(result.cues[0].voice, "off")
        XCTAssertEqual(result.positions?.first?.label, "À reprendre")
    }

    func testMarkerEditsAndSourceExtensionsArePreserved() throws {
        var project = try DetX.read(DetX.write(example()))
        project.loops = [Marker(frame: 80, label: "1")]
        project.shots = [Marker(frame: 110, label: "1")]
        let xml = try XMLDocument(data: DetX.write(project))
        let sign = try XCTUnwrap(xml.nodes(forXPath: "/detx/body/line/lipsync[2]").first as? XMLElement)
        sign.addAttribute(XMLNode.attribute(withName: "link", stringValue: "keep") as! XMLNode)
        project = try DetX.read(xml.xmlData(options: []))
        project.loops[0].frame = 85
        project.shots.removeAll()
        let output = try XMLDocument(data: DetX.write(project))
        XCTAssertEqual(try output.nodes(forXPath: "/detx/body/line/lipsync[2]/@link").first?.stringValue, "keep")
        XCTAssertTrue(try output.nodes(forXPath: "/detx/body/shot").isEmpty)
        XCTAssertEqual(try DetX.read(output.xmlData(options: [])).loops[0].frame, 85)
    }

    func testUnicodeAndLineBreaksRoundTrip() throws {
        var project = example()
        project.cues[0].replaceText("Été 👩🏽‍🚀\nBonjour !")
        let output = try DetX.read(DetX.write(project))
        XCTAssertEqual(output.cues[0].text, project.cues[0].text)
        try output.validate()
    }

    func testSignBetweenCombiningScalarsPreservesExactText() throws {
        var project = example()
        var cue = Cue(roleID: project.roles[0].id, start: 100, end: 200, text: "e\u{301}té")
        cue.signs = [SyncSign(frame: 100, textOffset: 0, kind: "in_open"),
                     SyncSign(frame: 110, textOffset: 1, kind: "neutral"),
                     SyncSign(frame: 200, textOffset: 4, kind: "out_open")]
        project.cues = [cue]
        let result = try DetX.read(DetX.write(project))
        XCTAssertEqual(Array(result.cues[0].text.unicodeScalars), Array(cue.text.unicodeScalars))
        XCTAssertEqual(result.cues[0].signs?.map(\.textOffset), [0, 1, 4])
    }

    func testCrossTableQuotesAndCountsByLoop() {
        var project = example()
        project.roles[0].name = "Rôle; \"A\""
        project.loops = [Marker(frame: 0, label: "1"), Marker(frame: 150, label: "2")]
        let rows = project.crossTableCSV().components(separatedBy: "\r\n")
        XCTAssertTrue(rows[0].contains("\"Rôle; \"\"A\"\"\""))
        XCTAssertTrue(rows[1].hasSuffix(";\"1\""))
        XCTAssertTrue(rows[2].hasSuffix(";\"0\""))
    }
}
