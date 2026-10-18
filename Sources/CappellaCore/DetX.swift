import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Native DetX reader/writer. Keeps the original XML and patches edited fields,
/// including intermediate lipsync/text runs instead of flattening them.
public enum DetX {
    private static let headerTexts = ["title2", "notes", "summary"]
    private static let headerAttributes: [String: [String]] = [
        "episode": ["number", "season", "title", "title2"],
        "production": ["actors", "country", "diffuser", "director", "distributor", "producer", "year"],
        "detector": ["firstname", "name"], "second-author": ["firstname", "name"]
    ]

    public static func read(_ data: Data, fps: Int = 25) throws -> Project {
        let document = try parse(data)
        guard let root = document.rootElement(), root.name == "detx",
              [24, 25, 30].contains(fps), root.elements(forName: "body").count == 1,
              root.elements(forName: "roles").count == 1 else {
            throw ProjectError.invalid("Structure ou cadence DetX non prise en charge.")
        }
        var project = Project()
        project.framesPerSecond = fps; project.originalDetX = data
        let header = root.elements(forName: "header").first
        project.title = header?.elements(forName: "title").first?.stringValue ?? "Sans titre"
        if let author = header?.elements(forName: "first-author").first {
            project.author = [attr(author, "firstname"), attr(author, "name")].compactMap { $0 }.joined(separator: " ")
        }
        var metadata: [String: String] = [:]
        for tag in headerTexts { metadata[tag] = header?.elements(forName: tag).first?.stringValue }
        for (tag, attributes) in headerAttributes {
            for name in attributes { metadata[tag + "." + name] = header?.elements(forName: tag).first.flatMap { attr($0, name) } }
        }
        project.metadata = metadata
        project.videoPath = header?.elements(forName: "videofile").first?.stringValue
        project.audioPath = header?.elements(forName: "audiofile").first?.stringValue
        if let timestamp = header?.elements(forName: "videofile").first.flatMap({ attr($0, "timestamp") }) {
            project.mediaStartFrame = try time(timestamp, fps: fps)
        }
        if let position = header?.elements(forName: "last_position").first.flatMap({ attr($0, "timecode") }) {
            project.lastPositionFrame = try time(position, fps: fps)
        }
        for (index, element) in (root.elements(forName: "roles").first?.elements(forName: "role") ?? []).enumerated() {
            guard let sourceID = attr(element, "id"), !project.roles.contains(where: { $0.sourceID == sourceID }) else {
                throw ProjectError.invalid("Identifiant de rôle absent ou dupliqué.")
            }
            var role = Role(name: attr(element, "name") ?? sourceID, color: index % 6)
            role.sourceID = sourceID; role.hexColor = attr(element, "color")
            role.descriptionText = attr(element, "description"); role.gender = attr(element, "gender")
            role.imageData = element.elements(forName: "image").first?.stringValue.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            project.roles.append(role)
        }
        for (index, node) in try document.nodes(forXPath: "/detx/body/line").enumerated() {
            guard let element = node as? XMLElement,
                  let track = attr(element, "track").flatMap(Int.init), (0...15).contains(track),
                  let role = project.roles.first(where: { $0.sourceID == attr(element, "role") }) else {
                throw ProjectError.invalid("Rôle ou piste invalide dans la phrase \(index + 1).")
            }
            var text = ""
            var signs: [SyncSign] = []
            for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                switch child.name {
                case "lipsync":
                    guard let timestamp = attr(child, "timecode"), let kind = attr(child, "type") else { throw ProjectError.invalid("Signe sans type ou timecode.") }
                    signs.append(SyncSign(frame: try time(timestamp, fps: fps), textOffset: text.unicodeScalars.count, kind: kind, sourceIndex: signs.count))
                case "text":
                    guard (child.children ?? []).allSatisfy({ $0.kind == .text }) else { throw ProjectError.invalid("Balises internes au texte non prises en charge.") }
                    text += child.stringValue ?? ""
                case "br": text += "\n"
                default:
                    throw ProjectError.invalid("Élément de phrase non pris en charge : \(child.name ?? "?"). Le fichier n'est pas modifié.")
                }
            }
            guard signs.count >= 2, let first = signs.first, let last = signs.last,
                  first.textOffset == 0, last.textOffset == text.unicodeScalars.count else { throw ProjectError.invalid("La phrase doit être délimitée par deux signes.") }
            var cue = Cue(roleID: role.id, start: first.frame, end: last.frame, text: text)
            cue.sourceIndex = index; cue.track = track; cue.signs = signs; cue.voice = attr(element, "voice")
            project.cues.append(cue)
        }
        for tag in ["loop", "shot"] {
            for (index, node) in try document.nodes(forXPath: "/detx/body/\(tag)").enumerated() {
                guard let element = node as? XMLElement, let timestamp = attr(element, "timecode") else { throw ProjectError.invalid("Repère invalide.") }
                var marker = Marker(frame: try time(timestamp, fps: fps), label: attr(element, "number") ?? String(index + 1))
                marker.sourceIndex = index
                if tag == "loop" { project.loops.append(marker) } else { project.shots.append(marker) }
            }
        }
        project.positions = try document.nodes(forXPath: "/detx/bookmark").enumerated().map { index, node -> Marker in
            guard let bookmark = node as? XMLElement, let timestamp = attr(bookmark, "timecode") else { throw ProjectError.invalid("Position mémorisée sans timecode.") }
            var marker = Marker(frame: try time(timestamp, fps: fps), label: attr(bookmark, "label") ?? "Position")
            marker.sourceIndex = index
            return marker
        }
        try project.validate()
        return project
    }

    public static func write(_ project: Project) throws -> Data {
        try project.validate()
        let document: XMLDocument
        if let original = project.originalDetX { document = try parse(original) }
        else { document = XMLDocument(rootElement: XMLElement(name: "detx")); document.version = "1.0"; document.characterEncoding = "UTF-8" }
        guard let root = document.rootElement() else { throw ProjectError.invalid("Document XML vide.") }
        let header = element(root, "header")
        element(header, "title").stringValue = project.title
        let originalAuthor = header.elements(forName: "first-author").first
        let authorName = originalAuthor.map { [attr($0, "firstname"), attr($0, "name")].compactMap { $0 }.joined(separator: " ") } ?? ""
        if project.author != authorName {
            let author = element(header, "first-author"); set(author, "firstname", ""); set(author, "name", project.author)
        }
        for tag in headerTexts {
            if let value = project.metadata?[tag] { element(header, tag).stringValue = value }
        }
        for (tag, names) in headerAttributes {
            for name in names {
                if let value = project.metadata?[tag + "." + name] { set(element(header, tag), name, value) }
            }
        }
        let video = element(header, "videofile")
        set(video, "timestamp", Timecode.format(project.mediaStartFrame, fps: project.framesPerSecond))
        if let path = project.videoPath { video.stringValue = path }
        if let path = project.audioPath { element(header, "audiofile").stringValue = path }
        if let position = project.lastPositionFrame {
            let last = element(header, "last_position"); set(last, "timecode", Timecode.format(position, fps: project.framesPerSecond))
            if attr(last, "track") == nil { set(last, "track", "0") }
        }
        let roles = element(root, "roles")
        var roleIDs: [UUID: String] = [:]
        for role in project.roles {
            let sourceID = role.sourceID ?? "mac_" + role.id.uuidString.lowercased()
            guard !roleIDs.values.contains(sourceID) else { throw ProjectError.invalid("Identifiants de rôles source dupliqués.") }
            roleIDs[role.id] = sourceID
            let node = roles.elements(forName: "role").first { attr($0, "id") == sourceID } ?? XMLElement(name: "role")
            if node.parent == nil { roles.addChild(node) }
            set(node, "id", sourceID); set(node, "name", role.name)
            if let value = role.hexColor { set(node, "color", value) }
            if let value = role.descriptionText { set(node, "description", value) }
            if let value = role.gender { set(node, "gender", value) }
            if let data = role.imageData { element(node, "image").stringValue = data.base64EncodedString() }
        }
        for role in roles.elements(forName: "role") where !roleIDs.values.contains(attr(role, "id") ?? "") { role.detach() }
        let body = element(root, "body")
        let originals = body.elements(forName: "line")
        let mapped = project.cues.compactMap(\.sourceIndex)
        guard Set(mapped).count == mapped.count, mapped.allSatisfy({ originals.indices.contains($0) }) else { throw ProjectError.invalid("Correspondance des phrases source invalide.") }
        for (index, line) in originals.enumerated() {
            guard let cue = project.cues.first(where: { $0.sourceIndex == index }) else { line.detach(); continue }
            try update(line, cue: cue, fps: project.framesPerSecond, roleIDs: roleIDs)
        }
        for cue in project.cues where cue.sourceIndex == nil {
            let line = XMLElement(name: "line")
            try update(line, cue: cue, fps: project.framesPerSecond, roleIDs: roleIDs)
            body.addChild(line)
        }
        try updateMarkers(body, tag: "loop", markers: project.loops, fps: project.framesPerSecond)
        try updateMarkers(body, tag: "shot", markers: project.shots, fps: project.framesPerSecond)
        // Bookmark tag and label attribute are present in the original reader.
        // The placement of newly created bookmarks still needs a Windows round-trip check.
        let originalBookmarks = root.elements(forName: "bookmark")
        for bookmark in originalBookmarks { bookmark.detach() }
        for position in project.positions ?? [] {
            let bookmark: XMLElement
            if let source = position.sourceIndex, originalBookmarks.indices.contains(source) { bookmark = originalBookmarks[source].copy() as! XMLElement }
            else { bookmark = XMLElement(name: "bookmark") }
            set(bookmark, "label", position.label)
            set(bookmark, "timecode", Timecode.format(position.frame, fps: project.framesPerSecond))
            root.addChild(bookmark)
        }
        // Cappella writes a chronological stream of loops, shots and phrases.
        var events: [XMLElement] = []
        for child in body.children ?? [] {
            guard let node = child as? XMLElement else { continue }
            if node.name == "line" || node.name == "loop" || node.name == "shot" { events.append(node) }
        }
        var ordered: [(frame: Int, originalOrder: Int, node: XMLElement)] = []
        for (index, node) in events.enumerated() {
            let timestamp: String?
            if node.name == "line", let firstSign = node.elements(forName: "lipsync").first {
                timestamp = attr(firstSign, "timecode")
            } else { timestamp = attr(node, "timecode") }
            let frame = try time(timestamp ?? "", fps: project.framesPerSecond)
            ordered.append((frame: frame, originalOrder: index, node: node))
        }
        ordered.sort { left, right in
            if left.frame == right.frame { return left.originalOrder < right.originalOrder }
            return left.frame < right.frame
        }
        for node in events { node.detach() }
        for event in ordered { body.addChild(event.node) }
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private static func update(_ line: XMLElement, cue: Cue, fps: Int, roleIDs: [UUID: String]) throws {
        guard let roleID = cue.roleID.flatMap({ roleIDs[$0] }) else { throw ProjectError.invalid("Toutes les phrases doivent avoir un rôle pour l'export DetX.") }
        set(line, "role", roleID); set(line, "track", String(cue.track))
        if let voice = cue.voice { set(line, "voice", voice) }
        else { line.removeAttribute(forName: "voice") }
        let originalSigns = line.elements(forName: "lipsync")
        let originalTexts = line.elements(forName: "text")
        // Existing node attributes (including link/type) are preserved.
        (line.children ?? []).forEach { $0.detach() }
        let signs = cue.anchors
        for (index, sign) in signs.enumerated() {
            let node: XMLElement
            if let source = sign.sourceIndex, originalSigns.indices.contains(source), let copy = originalSigns[source].copy() as? XMLElement { node = copy }
            else { node = XMLElement(name: "lipsync") }
            set(node, "type", sign.kind); set(node, "timecode", Timecode.format(sign.frame, fps: fps))
            line.addChild(node)
            if index + 1 < signs.count {
                let next = signs[index + 1]
                let scalars = cue.text.unicodeScalars
                let a = scalars.index(scalars.startIndex, offsetBy: sign.textOffset)
                let b = scalars.index(scalars.startIndex, offsetBy: next.textOffset)
                let templateIndex = sign.sourceIndex ?? signs.prefix(index + 1).reversed().compactMap(\.sourceIndex).first ?? 0
                let chunks = String(scalars[a..<b]).components(separatedBy: "\n")
                for (chunkIndex, chunk) in chunks.enumerated() {
                    if chunkIndex > 0 { line.addChild(XMLElement(name: "br")) }
                    let text = templateIndex < originalTexts.count ? originalTexts[templateIndex].copy() as! XMLElement : XMLElement(name: "text")
                    text.stringValue = chunk; line.addChild(text)
                }
            }
        }
    }

    private static func updateMarkers(_ body: XMLElement, tag: String, markers: [Marker], fps: Int) throws {
        let originals = body.elements(forName: tag)
        let mapped = markers.compactMap(\.sourceIndex)
        guard Set(mapped).count == mapped.count, mapped.allSatisfy({ originals.indices.contains($0) }) else { throw ProjectError.invalid("Correspondance des repères invalide.") }
        let copies = markers.map { marker -> XMLElement in
            let node: XMLElement
            if let source = marker.sourceIndex { node = originals[source].copy() as! XMLElement } else { node = XMLElement(name: tag) }
            set(node, "timecode", Timecode.format(marker.frame, fps: fps))
            if tag == "loop" { set(node, "number", marker.label) }
            return node
        }
        originals.forEach { $0.detach() }; copies.forEach { body.addChild($0) }
    }

    private static func parse(_ data: Data) throws -> XMLDocument {
        guard data.count < 50_000_000 else { throw ProjectError.invalid("Document DetX trop volumineux.") }
        let text = String(decoding: data, as: UTF8.self).uppercased()
        guard !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else { throw ProjectError.invalid("Les déclarations DTD/entités ne sont pas prises en charge.") }
        return try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
    }
    private static func time(_ text: String, fps: Int) throws -> Int {
        guard let value = Timecode.parse(text, fps: fps) else { throw ProjectError.invalid("Timecode invalide : \(text)") }
        return value
    }
    private static func attr(_ node: XMLElement, _ name: String) -> String? { node.attribute(forName: name)?.stringValue }
    private static func set(_ node: XMLElement, _ name: String, _ value: String) {
        if let attribute = node.attribute(forName: name) { attribute.stringValue = value }
        else { node.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode) }
    }
    private static func element(_ parent: XMLElement, _ name: String) -> XMLElement {
        if let node = parent.elements(forName: name).first { return node }
        let node = XMLElement(name: name); parent.addChild(node); return node
    }
}
