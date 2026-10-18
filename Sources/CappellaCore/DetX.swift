import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Édition du profil observé : lipsync / text / lipsync.
/// Le XML source reste dans le projet pour conserver les champs non exposés.
public enum DetX {
    public static func read(_ data: Data, fps: Int = 25) throws -> Project {
        let document = try parse(data)
        guard let root = document.rootElement(), root.name == "detx" else {
            throw ProjectError.invalid("Ce fichier n'est pas un document DetX.")
        }
        guard [24, 25, 30].contains(fps), root.elements(forName: "body").count == 1,
              root.elements(forName: "roles").count == 1 else { throw ProjectError.invalid("Structure ou cadence DetX non prise en charge.") }
        var project = Project()
        project.framesPerSecond = fps
        project.originalDetX = data
        let header = root.elements(forName: "header").first
        project.title = header?.elements(forName: "title").first?.stringValue ?? "Sans titre"
        if let author = header?.elements(forName: "first-author").first {
            project.author = [attr(author, "firstname"), attr(author, "name")].compactMap { $0 }.joined(separator: " ")
        }
        if let timestamp = header?.elements(forName: "videofile").first.flatMap({ attr($0, "timestamp") }) {
            guard let value = Timecode.parse(timestamp, fps: fps) else { throw ProjectError.invalid("Timecode vidéo invalide.") }
            project.mediaStartFrame = value
        }
        for (index, element) in (root.elements(forName: "roles").first?.elements(forName: "role") ?? []).enumerated() {
            guard let sourceID = attr(element, "id"), !project.roles.contains(where: { $0.sourceID == sourceID }) else {
                throw ProjectError.invalid("Identifiant de rôle absent ou dupliqué.")
            }
            var role = Role(name: attr(element, "name") ?? sourceID, color: index % 6)
            role.sourceID = sourceID; role.hexColor = attr(element, "color")
            project.roles.append(role)
        }
        for (index, node) in try document.nodes(forXPath: "/detx/body/line").enumerated() {
            guard let element = node as? XMLElement else { continue }
            let children = element.children?.compactMap { $0 as? XMLElement } ?? []
            guard children.map(\.name) == ["lipsync", "text", "lipsync"],
                  (children[1].children ?? []).allSatisfy({ $0.kind == .text }),
                  let start = attr(children[0], "timecode").flatMap({ Timecode.parse($0, fps: fps) }),
                  let end = attr(children[2], "timecode").flatMap({ Timecode.parse($0, fps: fps) }),
                  let track = attr(element, "track").flatMap(Int.init), (0...15).contains(track) else {
                throw ProjectError.invalid("Structure de phrase non encore prise en charge (phrase \(index + 1)). Le fichier source reste intact.")
            }
            let role = project.roles.first { $0.sourceID == attr(element, "role") }
            guard let role else { throw ProjectError.invalid("Rôle inconnu dans la phrase \(index + 1).") }
            var cue = Cue(roleID: role.id, start: start, end: end, text: children[1].stringValue ?? "")
            cue.sourceIndex = index; cue.track = track
            project.cues.append(cue)
        }
        for tag in ["loop", "shot"] {
            for (index, node) in try document.nodes(forXPath: "/detx/body/\(tag)").enumerated() {
                guard let element = node as? XMLElement,
                      let frame = attr(element, "timecode").flatMap({ Timecode.parse($0, fps: fps) }) else {
                    throw ProjectError.invalid("Repère \(tag) invalide.")
                }
                let marker = Marker(frame: frame, label: attr(element, "number") ?? String(index + 1))
                if tag == "loop" { project.loops.append(marker) } else { project.shots.append(marker) }
            }
        }
        try project.validate()
        return project
    }

    public static func write(_ project: Project) throws -> Data {
        try project.validate()
        guard let original = project.originalDetX else { throw ProjectError.invalid("L'export DetX nécessite un document DetX importé.") }
        let document = try parse(original)
        guard let root = document.rootElement(), let body = root.elements(forName: "body").first,
              let roles = root.elements(forName: "roles").first else { throw ProjectError.invalid("Structure DetX incomplète.") }
        let initial = try read(original, fps: project.framesPerSecond)
        guard project.mediaStartFrame == initial.mediaStartFrame else { throw ProjectError.invalid("Origine vidéo modifiée : export refusé.") }
        let header = root.elements(forName: "header").first
        header?.elements(forName: "title").first?.stringValue = project.title
        if let author = header?.elements(forName: "first-author").first, project.author != initial.author {
            set(author, "firstname", ""); set(author, "name", project.author)
        }
        var roleIDs: [UUID: String] = [:]
        for role in project.roles {
            let sourceID = role.sourceID ?? "mac_" + role.id.uuidString.lowercased()
            roleIDs[role.id] = sourceID
            let element: XMLElement
            if let existing = roles.elements(forName: "role").first(where: { attr($0, "id") == sourceID }) { element = existing }
            else { element = XMLElement(name: "role"); set(element, "id", sourceID); roles.addChild(element) }
            set(element, "name", role.name)
            if let color = role.hexColor { set(element, "color", color) }
        }
        let originals = body.elements(forName: "line")
        let mapped = project.cues.compactMap(\.sourceIndex)
        guard Set(mapped).count == mapped.count, mapped.allSatisfy({ originals.indices.contains($0) }) else {
            throw ProjectError.invalid("Correspondance des phrases source invalide.")
        }
        for (index, line) in originals.enumerated() {
            guard let cue = project.cues.first(where: { $0.sourceIndex == index }) else { line.detach(); continue }
            try update(line, cue: cue, fps: project.framesPerSecond, roleIDs: roleIDs)
        }
        for cue in project.cues where cue.sourceIndex == nil {
            let line = XMLElement(name: "line")
            let begin = XMLElement(name: "lipsync"); set(begin, "type", "in_open")
            let end = XMLElement(name: "lipsync"); set(end, "type", "out_open")
            line.addChild(begin); line.addChild(XMLElement(name: "text")); line.addChild(end)
            try update(line, cue: cue, fps: project.framesPerSecond, roleIDs: roleIDs)
            body.addChild(line)
        }
        // Les rôles source inutilisés restent conservés, portraits et descriptions compris.
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private static func update(_ line: XMLElement, cue: Cue, fps: Int, roleIDs: [UUID: String]) throws {
        guard let roleID = cue.roleID.flatMap({ roleIDs[$0] }) else {
            throw ProjectError.invalid("Toutes les phrases doivent avoir un rôle pour l'export DetX.")
        }
        set(line, "role", roleID); set(line, "track", String(cue.track))
        let lips = line.elements(forName: "lipsync")
        guard lips.count == 2, let text = line.elements(forName: "text").first else { throw ProjectError.invalid("Phrase DetX invalide.") }
        set(lips[0], "timecode", Timecode.format(cue.start, fps: fps))
        set(lips[1], "timecode", Timecode.format(cue.end, fps: fps))
        text.stringValue = cue.text
    }
    private static func parse(_ data: Data) throws -> XMLDocument {
        guard data.count < 50_000_000 else { throw ProjectError.invalid("Document DetX trop volumineux.") }
        let text = String(decoding: data, as: UTF8.self).uppercased()
        guard !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else { throw ProjectError.invalid("Les déclarations DTD/entités ne sont pas prises en charge.") }
        return try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
    }
    private static func attr(_ element: XMLElement, _ name: String) -> String? { element.attribute(forName: name)?.stringValue }
    private static func set(_ element: XMLElement, _ name: String, _ value: String) {
        if let attribute = element.attribute(forName: name) { attribute.stringValue = value }
        else { element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode) }
    }
}
