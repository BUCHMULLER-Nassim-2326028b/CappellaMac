import Foundation

public struct Role: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var color: Int
    public var sourceID: String?
    public var hexColor: String?
    public init(id: UUID = UUID(), name: String, color: Int = 0) {
        self.id = id; self.name = name; self.color = color
    }
}

public struct Cue: Codable, Identifiable, Equatable {
    public var id: UUID
    public var roleID: UUID?
    public var start: Int
    public var end: Int
    public var text: String
    public var sourceIndex: Int?
    public var track: Int = 0
    public init(id: UUID = UUID(), roleID: UUID? = nil, start: Int, end: Int, text: String = "") {
        self.id = id; self.roleID = roleID; self.start = start; self.end = end; self.text = text
    }
}

public struct Project: Codable, Equatable {
    public var formatVersion = 1
    public var title = "Sans titre"
    public var author = ""
    public var framesPerSecond = 25
    public var roles: [Role] = []
    public var cues: [Cue] = []
    public var mediaStartFrame: Int = 0
    public var originalDetX: Data?
    public var loops: [Marker] = []
    public var shots: [Marker] = []
    public init() {}

    public func validate() throws {
        guard formatVersion == 1 else { throw ProjectError.invalid("Version de projet non prise en charge.") }
        guard [24, 25, 30].contains(framesPerSecond) else {
            throw ProjectError.invalid("Cadence non prise en charge (24, 25 ou 30 images/s).")
        }
        guard Set(roles.map(\.id)).count == roles.count, Set(cues.map(\.id)).count == cues.count else {
            throw ProjectError.invalid("Identifiants dupliqués.")
        }
        guard mediaStartFrame >= 0, mediaStartFrame <= 999 * 3600 * framesPerSecond else {
            throw ProjectError.invalid("Origine média invalide.")
        }
        let ids = Set(roles.map(\.id))
        for cue in cues {
            guard cue.start >= 0, cue.end > cue.start, cue.end <= 999 * 3600 * framesPerSecond,
                  (0...15).contains(cue.track) else {
                throw ProjectError.invalid("Une phrase a des bornes temporelles ou une piste invalides.")
            }
            if let role = cue.roleID, !ids.contains(role) {
                throw ProjectError.invalid("Une phrase référence un rôle absent.")
            }
        }
    }

    public static func decode(_ data: Data) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: data)
        try project.validate()
        return project
    }

    public func encode() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct Marker: Codable, Identifiable, Equatable {
    public var id: UUID
    public var frame: Int
    public var label: String
    public init(frame: Int, label: String) { id = UUID(); self.frame = frame; self.label = label }
}

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Timecodes non-drop-frame. Les cadences fractionnaires nécessiteront un modèle rationnel.
public enum Timecode {
    public static func format(_ frames: Int, fps: Int) -> String {
        guard fps > 0 else { return "--:--:--:--" }
        let f = max(0, frames)
        return String(format: "%02d:%02d:%02d:%02d", f / (fps * 3600), (f / (fps * 60)) % 60, (f / fps) % 60, f % fps)
    }

    public static func parse(_ text: String, fps: Int) -> Int? {
        guard [24, 25, 30].contains(fps) else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4, values[0] <= 999, values[1] < 60, values[2] < 60, values[3] < fps else { return nil }
        return ((values[0] * 60 + values[1]) * 60 + values[2]) * fps + values[3]
    }
}
