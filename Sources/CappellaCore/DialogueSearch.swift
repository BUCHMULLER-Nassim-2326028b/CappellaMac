import Foundation

/// Identical literal matching and chronological navigation on both platforms.
public struct DialogueSearch: Equatable {
    public var text = ""
    public var roleID: UUID?
    public var caseSensitive = false
    public var wholeWord = false

    public init() {}

    public func next(in cues: [Cue], after frame: Int, selection: UUID?) -> Cue? {
        guard !text.isEmpty else { return nil }
        let regex: NSRegularExpression?
        if wholeWord {
            let word = "[\\p{L}\\p{M}\\p{N}_]"
            let pattern = "(?<!" + word + ")" + NSRegularExpression.escapedPattern(for: text) + "(?!" + word + ")"
            regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
        } else { regex = nil }
        var matches: [(index: Int, cue: Cue)] = []
        for (index, cue) in cues.enumerated() {
            guard roleID == nil || cue.roleID == roleID else { continue }
            let found: Bool
            if wholeWord {
                let range = NSRange(cue.text.startIndex..., in: cue.text)
                found = regex?.firstMatch(in: cue.text, range: range) != nil
            } else {
                found = cue.text.range(of: text, options: caseSensitive ? [] : [.caseInsensitive]) != nil
            }
            if found { matches.append((index, cue)) }
        }
        matches.sort { left, right in
            if left.cue.start != right.cue.start { return left.cue.start < right.cue.start }
            if left.cue.track != right.cue.track { return left.cue.track < right.cue.track }
            return left.index < right.index
        }
        guard !matches.isEmpty else { return nil }
        // Advance through simultaneous phrases as well, then wrap to the start.
        if let index = matches.firstIndex(where: { $0.cue.id == selection && $0.cue.start == frame }) {
            return matches[(index + 1) % matches.count].cue
        }
        return (matches.first(where: { $0.cue.start >= frame }) ?? matches.first)?.cue
    }
}
