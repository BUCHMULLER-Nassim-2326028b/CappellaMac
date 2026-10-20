import Foundation

public extension Cue {
    /// Keep the letters already attached to signs when editing another part of
    /// the phrase. Offsets are Unicode scalars, as in the DetX reader/writer.
    mutating func editText(_ replacement: String) {
        let old = Array(text.unicodeScalars), new = Array(replacement.unicodeScalars)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let oldEnd = old.count - suffix
        let newEnd = new.count - suffix
        var values = anchors
        for i in values.indices {
            let offset = values[i].textOffset
            if offset > prefix {
                values[i].textOffset = offset >= oldEnd ? offset + new.count - old.count : newEnd
            }
        }
        values[0].textOffset = 0; values[values.count - 1].textOffset = new.count
        text = replacement; signs = values
    }
}


/// Word selection shared independently of native text-control coordinates.
/// Offsets use Unicode scalars, like DetX signs and the dialogue editor.
public enum DialogueTextSelection {
    public static func wordRange(in text: String, at offset: Int) -> Range<Int> {
        let characters = Array(text)
        guard !characters.isEmpty else { return 0..<0 }
        var boundaries = [0]
        for character in characters { boundaries.append(boundaries.last! + character.unicodeScalars.count) }
        let wordSet = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        var kinds = characters.map { character -> Int in
            if character == "_" || character.unicodeScalars.contains(where: { wordSet.contains($0) }) { return 1 }
            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { return 2 }
            return 0
        }
        // Apostrophes and hyphens join the letters around them, e.g. l'équipe.
        if characters.count > 2 {
            for index in 1..<(characters.count - 1) where
                ["'", "’", "-"].contains(String(characters[index])) && kinds[index - 1] == 1 && kinds[index + 1] == 1 {
                kinds[index] = 1
            }
        }
        let target = min(max(0, offset), boundaries.last! - 1)
        let index = max(0, (0..<characters.count).first(where: { boundaries[$0 + 1] > target }) ?? characters.count - 1)
        var start = index, end = index + 1
        if kinds[index] != 0 {
            while start > 0 && kinds[start - 1] == kinds[index] { start -= 1 }
            while end < characters.count && kinds[end] == kinds[index] { end += 1 }
        }
        return boundaries[start]..<boundaries[end]
    }
}
