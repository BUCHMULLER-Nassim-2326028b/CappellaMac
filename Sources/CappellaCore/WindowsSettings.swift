#if os(Windows)
import Foundation

/// Explicit per-user storage: independent of executable name, build directory
/// and the lifetime of the WinUI message loop.
public enum WindowsSettings {
    public static var fileURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let folder = environment["APPDATA"] ?? environment["LOCALAPPDATA"]
        let base = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("AppData/Roaming")
        return base.appendingPathComponent("Cappella/preferences.json")
    }
    public static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return values
    }
    public static func merge(_ changes: [String: Any]) throws {
        var values = read()
        for (key, value) in changes { values[key] = value }
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
    public static func number(forKey key: String) -> Double {
        (read()[key] as? NSNumber)?.doubleValue ?? UserDefaults.standard.double(forKey: key)
    }
}
#endif