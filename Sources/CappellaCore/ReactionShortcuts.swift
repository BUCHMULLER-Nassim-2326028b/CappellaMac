/// Reaction text from Cappella's keyboard reference, shared by both interfaces.
public enum ReactionShortcuts {
    private static let phrases: [String: String] = [
        "a": "ah", "e": "(effort)", "r": "(réac)", "t": "tst",
        "u": "euh", "U": "huh", "i": "(rire)", "o": "oh", "O": "OUT",
        "p": "(peur)", "s": "sniff", "f": "fff", "F": "(_fin)",
        "g": "grrr", "G": "argh!", "h": "hhh", "H": "han!",
        "j": "(joie)", "l": "(pleurs)", "m": "mts", "M": "mmm",
        "x": "X", "?": "(réac ?)", "c": "(course)"
    ]
    public static func text(for character: String) -> String? {
        phrases[character] ?? phrases[character.lowercased()]
    }
}
