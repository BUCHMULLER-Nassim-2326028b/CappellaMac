import Foundation
import XCTest
@testable import CappellaCore

final class SharedEditingTests: XCTestCase {
    private func example() -> Project {
        var project = Project()
        project.roles = [Role(name: "Alice")]
        return project
    }
    func testDraftHasNoVisibleEndAndEnterFinalizesAtPlayhead() throws {
        var project = example()
        let cue = try ProjectEditing.createPhrase(in: &project, role: project.roles[0].id, frame: 0, track: 0, text: "Bonjour")
        XCTAssertEqual(cue.visibleAnchors.count, 1)
        try ProjectEditing.finalizePhrase(in: &project, id: cue.id, frame: 175)
        XCTAssertNil(project.cues[0].pendingEnd)
        XCTAssertEqual(project.cues[0].end, 175)
        XCTAssertEqual(project.cues[0].visibleAnchors.last?.frame, 175)
    }
    func testDraftTextUsesNaturalWidthUntilItsOutSignIsPlaced() throws {
        var project = example()
        let cue = try ProjectEditing.createPhrase(in: &project, role: project.roles[0].id, frame: 25, track: 0, text: "Bonjour")
        XCTAssertEqual(Timeline.segments(cue).map(\.naturalWidth), [true])
        try ProjectEditing.finalizePhrase(in: &project, id: cue.id, frame: 100)
        XCTAssertEqual(Timeline.segments(project.cues[0]).map(\.naturalWidth), [false])
        XCTAssertEqual(Timeline.segments(project.cues[0], editing: true).map(\.naturalWidth), [false])
    }
    func testPendingPhraseSurvivesDetXWithoutInventingAnOutSign() throws {
        var project = example()
        _ = try ProjectEditing.createPhrase(in: &project, role: project.roles[0].id, frame: 25, track: 0, text: "À suivre")
        let data = try DetX.write(project)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("out_open"))
        let restored = try DetX.read(data)
        XCTAssertEqual(restored.cues.first?.text, "À suivre")
        XCTAssertEqual(restored.cues.first?.pendingEnd, true)
    }
    func testPastingAcrossLoopIsAllowedButOverlappingAnotherPhraseIsRejected() throws {
        var project = example()
        let cue = Cue(roleID: project.roles[0].id, start: 0, end: 100, text: "Texte")
        project.loops = [Marker(frame: 50, label: "1")]
        _ = try ProjectEditing.paste(cue, into: &project, frame: 0, track: 0, roleID: cue.roleID)
        let unchanged = project
        XCTAssertThrowsError(try ProjectEditing.paste(cue, into: &project, frame: 10, track: 0, roleID: cue.roleID))
        XCTAssertEqual(project, unchanged)
    }
    func testHistoryGroupsTypingAndCancellationRestoresRedo() {
        let original = example()
        var edited = original; edited.author = "A"
        var history = ProjectHistory()
        history.record(before: original, after: edited)
        XCTAssertEqual(history.undo(edited), original)
        history.beginGroup(original)
        history.record(before: original, after: edited)
        XCTAssertEqual(history.cancelGroup(), original)
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.redo(original), edited)
    }
    func testMarkersAreRenumberedChronologically() {
        var project = example()
        ProjectEditing.addMarker(in: &project, frame: 100, loop: true)
        ProjectEditing.addMarker(in: &project, frame: 25, loop: true)
        XCTAssertEqual(project.loops.map(\.frame), [25, 100])
        XCTAssertEqual(project.loops.map(\.label), ["1", "2"])
    }
    func testPCMChannelsAndReversePreserveSampleFrames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("stereo.wav")
        var wav = Data("RIFF".utf8)
        func append(_ value: Int, _ bytes: Int) {
            for byte in 0..<bytes { wav.append(UInt8(truncatingIfNeeded: value >> (byte * 8))) }
        }
        append(44, 4); wav.append(Data("WAVEfmt ".utf8))
        append(16, 4); append(1, 2); append(2, 2); append(48000, 4); append(192000, 4)
        append(4, 2); append(16, 2); wav.append(Data("data".utf8)); append(8, 4)
        for sample in [1, 10, 2, 20] { append(sample, 2) }
        try wav.write(to: input)
        let tracks = try PCMChannelPreparation.prepare([input], in: directory.appendingPathComponent("split"))
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(Array(try Data(contentsOf: tracks[0]).suffix(4)), [1, 0, 2, 0])
        XCTAssertEqual(Array(try Data(contentsOf: tracks[1]).suffix(4)), [10, 0, 20, 0])
        let reverse = try PCMChannelPreparation.prepare([tracks[0]], in: directory.appendingPathComponent("reverse"),
                                                       reverse: true, routeChannels: false)
        XCTAssertEqual(Array(try Data(contentsOf: reverse[0]).suffix(4)), [2, 0, 1, 0])
        let cache = try PCMPlaybackCache.prepare([input])
        XCTAssertEqual(Array(try Data(contentsOf: cache.reverse[0]).suffix(4)), [2, 0, 1, 0])
        XCTAssertEqual(Array(try Data(contentsOf: cache.reverse[1]).suffix(4)), [20, 0, 10, 0])
        let reused = try PCMPlaybackCache.prepare([input], decode: {
            XCTFail("An existing cache must be used before invoking the native decoder.")
            return []
        })
        XCTAssertEqual(reused.reverse, cache.reverse)
    }
    func testAIFFStreamingAndReversePreserveChannelSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("stereo.aiff")
        var aiff = Data("FORM".utf8)
        func append(_ value: Int, _ count: Int) {
            for byte in (0..<count).reversed() { aiff.append(UInt8(truncatingIfNeeded: value >> (8 * byte))) }
        }
        append(54, 4); aiff.append(Data("AIFFCOMM".utf8)); append(18, 4)
        append(2, 2); append(2, 4); append(16, 2)
        aiff.append(contentsOf: [0x40, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]) // 48000 Hz
        aiff.append(Data("SSND".utf8)); append(16, 4); append(0, 4); append(0, 4)
        for sample in [1, 10, 2, 20] { append(sample, 2) }
        try aiff.write(to: source)
        do {
            let reader = try PCMChannelPreparation.Stream(source)
            XCTAssertEqual(reader.sampleRate, 48000)
            XCTAssertEqual(reader.bitsPerSample, 16)
            XCTAssertEqual(Array(try reader.read(frame: 1, count: 1, channels: [0])), [2, 0])
            XCTAssertEqual(Array(try reader.read(frame: 0, count: 1, channels: [1])), [10, 0])
            XCTAssertEqual(Array(try reader.read(frame: 1, count: 1, channels: [1])), [20, 0])
        }
        let tracks = try PCMChannelPreparation.prepare([source], in: directory.appendingPathComponent("forward"))
        let reverse = try PCMChannelPreparation.prepare([source], in: directory.appendingPathComponent("reverse"), reverse: true)
        XCTAssertEqual(Array(try Data(contentsOf: tracks[0]).suffix(4)), [1, 0, 2, 0])
        XCTAssertEqual(Array(try Data(contentsOf: tracks[1]).suffix(4)), [10, 0, 20, 0])
        XCTAssertEqual(Array(try Data(contentsOf: reverse[0]).suffix(4)), [2, 0, 1, 0])
        XCTAssertEqual(Array(try Data(contentsOf: reverse[1]).suffix(4)), [20, 0, 10, 0])
    }
}
