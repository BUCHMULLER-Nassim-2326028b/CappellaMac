import XCTest
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import CappellaCore

final class CoreTests: XCTestCase {
    private let fixture = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <detx copyright="Fixture indépendante">
      <header><cappella version="3.7.0"/><title>Épisode test</title><title2>Original</title2>
        <first-author firstname="Ada" name="Test"/><production year="2021"/>
        <videofile timestamp="10:00:00:00">D:\\film.mp4</videofile><custom keep="yes"/></header>
      <roles><role id="alice" name="Alice" color="#000000" description="Portrait conservé"><image>YWJj</image></role></roles>
      <body>
        <loop number="1" timecode="10:00:01:00"/><shot timecode="10:00:01:12"/>
        <line role="alice" track="3"><lipsync timecode="10:00:02:00" type="in_open"/><text>Bonjour &amp; salut !</text><lipsync timecode="10:00:04:12" type="out_open"/></line>
        <extension arbitrary="preserved"/>
      </body>
    </detx>
    """.utf8)

    func testTimecodeRoundTrips() {
        for fps in [24, 25, 30] {
            for frame in [0, 1, fps - 1, fps, fps * 60, fps * 36000 + 18] {
                XCTAssertEqual(Timecode.parse(Timecode.format(frame, fps: fps), fps: fps), frame)
            }
        }
        for text in ["-1:00:00:00", "00:60:00:00", "00:00:00:25", "00:00:00", ":::", "99999999999:00:00:00"] {
            XCTAssertNil(Timecode.parse(text, fps: 25))
        }
    }

    func testDetXReadsOriginTracksAndMarkers() throws {
        let project = try DetX.read(fixture)
        XCTAssertEqual(project.title, "Épisode test")
        XCTAssertEqual(project.author, "Ada Test")
        XCTAssertEqual(project.mediaStartFrame, 900000)
        XCTAssertEqual(project.cues[0].start - project.mediaStartFrame, 50)
        XCTAssertEqual(project.cues[0].end, 900112)
        XCTAssertEqual(project.cues[0].track, 3)
        XCTAssertEqual(project.cues[0].text, "Bonjour & salut !")
        XCTAssertEqual(project.loops.count, 1)
        XCTAssertEqual(project.shots.count, 1)
        XCTAssertEqual(try Project.decode(project.encode()), project)
    }

    func testExportEditsAndPreservesUnexposedData() throws {
        var project = try DetX.read(fixture)
        project.cues[0].replaceText("Ça <marche> & voilà !")
        try project.cues[0].setBounds(start: project.cues[0].start + 2, end: project.cues[0].end)
        project.roles[0].name = "Alice modifiée"
        let output = try DetX.write(project)
        let reloaded = try DetX.read(output)
        XCTAssertEqual(reloaded.cues[0].text, project.cues[0].text)
        XCTAssertEqual(reloaded.cues[0].start, project.cues[0].start)
        XCTAssertEqual(reloaded.roles[0].name, "Alice modifiée")
        let xml = try XMLDocument(data: output)
        for path in ["/detx/header/custom[@keep='yes']", "/detx/header/production[@year='2021']", "/detx/body/extension[@arbitrary='preserved']", "/detx/body/loop", "/detx/body/shot"] {
            XCTAssertEqual(try xml.nodes(forXPath: path).count, 1, path)
        }
        XCTAssertEqual(try xml.nodes(forXPath: "/detx/roles/role/image").first?.stringValue, "YWJj")
        XCTAssertEqual(try xml.nodes(forXPath: "/detx/roles/role/@description").first?.stringValue, "Portrait conservé")
    }

    func testNewAndDeletedPhrases() throws {
        var project = try DetX.read(fixture)
        project.cues.removeAll()
        project.cues.append(Cue(roleID: project.roles[0].id, start: 900200, end: 900250, text: "Nouvelle phrase"))
        let reloaded = try DetX.read(DetX.write(project))
        XCTAssertEqual(reloaded.cues.count, 1)
        XCTAssertEqual(reloaded.cues[0].text, "Nouvelle phrase")
        XCTAssertEqual(reloaded.loops.count, 1)
    }

    func testRefusesInvalidDocumentsAndMappings() throws {
        XCTAssertThrowsError(try DetX.read(Data("<detx/>".utf8)))
        XCTAssertThrowsError(try DetX.read(Data("<!DOCTYPE detx><detx/>".utf8)))
        var project = try DetX.read(fixture)
        project.cues[0].end = project.cues[0].start
        XCTAssertThrowsError(try project.encode())
        project = try DetX.read(fixture)
        project.cues[0].sourceIndex = 42
        XCTAssertThrowsError(try DetX.write(project))
        project = try DetX.read(fixture)
        project.cues[0].roleID = UUID()
        XCTAssertThrowsError(try DetX.write(project))
        let complex = String(decoding: fixture, as: UTF8.self).replacingOccurrences(of: "Bonjour &amp; salut !", with: "Bonjour <em>salut</em>")
        XCTAssertThrowsError(try DetX.read(Data(complex.utf8)))
    }

    func testPrivateSampleWhenProvidedLocally() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPPELLA_DETX_PATH"] else {
            throw XCTSkip("Définir CAPPELLA_DETX_PATH sur un Mac pour tester le fichier réel, sans le publier.")
        }
        let project = try DetX.read(Data(contentsOf: URL(fileURLWithPath: path)))
        let output = try DetX.read(DetX.write(project))
        XCTAssertEqual(output.cues.map(\.text), project.cues.map(\.text))
        XCTAssertEqual(output.cues.map(\.start), project.cues.map(\.start))
        XCTAssertEqual(output.cues.map(\.end), project.cues.map(\.end))
        XCTAssertEqual(output.cues.map(\.track), project.cues.map(\.track))
        XCTAssertEqual(output.roles.map(\.sourceID), project.roles.map(\.sourceID))
        XCTAssertEqual(output.loops.map(\.frame), project.loops.map(\.frame))
        XCTAssertEqual(output.shots.map(\.frame), project.shots.map(\.frame))
    }
}
