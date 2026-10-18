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
