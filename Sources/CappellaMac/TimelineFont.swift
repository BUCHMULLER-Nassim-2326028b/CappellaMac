import AppKit
import CoreText
import CappellaCore

enum TimelineFont {
    static func register() {
        let packaged = Bundle.main.resourceURL
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("packaging/Resources")
        for file in ["PreludeFLF.ttf", "PreludeFLF-Italic.ttf", "PreludeFLF-Bold.ttf", "PreludeFLF-BoldItalic.ttf"] {
            let candidates = [packaged?.appendingPathComponent(file), development.appendingPathComponent(file)].compactMap { $0 }
            if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    static func faceName(_ name: String) -> String {
        name == ApplicationPreferences.defaultFontName ? "PreludeFLF-Italic" : name
    }
    static func font(name: String, size: Double) -> NSFont {
        NSFont(name: faceName(name), size: CGFloat(size)) ?? .systemFont(ofSize: CGFloat(size))
    }
}