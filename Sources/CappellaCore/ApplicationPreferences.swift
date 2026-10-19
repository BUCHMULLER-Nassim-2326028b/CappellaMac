import Foundation

public struct ApplicationPreferences: Equatable {
    public var checkUpdates = false
    public var prefixCopies = true
    public var appearance = "light"
    public var automaticSave = true
    public var saveInterval = 5
    public var closeReactions = false
    public var showControlAtLaunch = false
    public var videoOffsetMilliseconds = 0.0
    public var fontName = "Apple Chancery"
    public var fontSize = 28.0
    public var pixelsPerSecond = 120.0
    public var bandHeight = 146.0
    public var showGrid = true
    public var showDetection = true

    public init() {}
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        #if os(Windows)
        let persisted = defaults === UserDefaults.standard ? WindowsSettings.read() : [:]
        #else
        let persisted: [String: Any] = [:]
        #endif
        func object(_ key: String) -> Any? { persisted[key] ?? defaults.object(forKey: key) }
        func string(_ key: String) -> String? { object(key) as? String }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            if let saved = persisted[key] as? NSNumber { return saved.boolValue }
            return defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        func number(_ key: String, _ fallback: Double) -> Double {
            guard object(key) != nil else { return fallback }
            let value = (persisted[key] as? NSNumber)?.doubleValue ?? defaults.double(forKey: key)
            return value.isFinite ? value : fallback
        }
        value.checkUpdates = bool("general.checkUpdates", false)
        value.prefixCopies = bool("general.prefixCopies", true)
        value.appearance = string("general.appearance") == "dark" ? "dark" : "light"
        value.automaticSave = bool("save.automatic", true)
        value.saveInterval = Int(min(120, max(1, number("save.intervalMinutes", 5))))
        value.closeReactions = bool("rythmo.closeReactions", false)
        value.showControlAtLaunch = bool("video.showControlAtLaunch", false)
        value.videoOffsetMilliseconds = min(1000, max(-1000, number("video.offsetMilliseconds", 0)))
        value.fontName = string("rythmo.font") ?? value.fontName
        value.fontSize = number("rythmo.fontSize", 28)
        #if os(Windows)
        // Windows previously multiplied this value in the renderer. Keep the
        // actual logical pixels/second explicit and independent of macOS defaults.
        value.pixelsPerSecond = min(800, max(15, number("rythmo.windowsPixelsPerSecond", 320)))
        if ["Apple Chancery", "Snell Roundhand", "Segoe Script"].contains(value.fontName) {
            value.fontName = "Monotype Corsiva"
        }
        #else
        value.pixelsPerSecond = number("rythmo.pixelsPerSecond", 120)
        #endif
        #if os(Windows)
        value.bandHeight = number("rythmo.height", 192)
        #else
        value.bandHeight = number("rythmo.height", 146)
        #endif
        value.showGrid = bool("rythmo.grid", true)
        value.showDetection = bool("rythmo.detection", true)
        return value
    }
    @discardableResult public func save(to defaults: UserDefaults = .standard) -> Bool {
        defaults.set(checkUpdates, forKey: "general.checkUpdates")
        defaults.set(prefixCopies, forKey: "general.prefixCopies")
        defaults.set(appearance == "dark" ? "dark" : "light", forKey: "general.appearance")
        defaults.set(automaticSave, forKey: "save.automatic")
        defaults.set(min(120, max(1, saveInterval)), forKey: "save.intervalMinutes")
        defaults.set(closeReactions, forKey: "rythmo.closeReactions")
        defaults.set(showControlAtLaunch, forKey: "video.showControlAtLaunch")
        defaults.set(min(1000, max(-1000, videoOffsetMilliseconds)), forKey: "video.offsetMilliseconds")
        defaults.set(fontName, forKey: "rythmo.font")
        defaults.set(fontSize, forKey: "rythmo.fontSize")
        defaults.set(pixelsPerSecond, forKey: "rythmo.pixelsPerSecond")
        #if os(Windows)
        defaults.set(pixelsPerSecond, forKey: "rythmo.windowsPixelsPerSecond")
        #endif
        defaults.set(bandHeight, forKey: "rythmo.height")
        defaults.set(showGrid, forKey: "rythmo.grid")
        defaults.set(showDetection, forKey: "rythmo.detection")
        #if os(Windows)
        if defaults === UserDefaults.standard {
            let values: [String: Any] = [
                "general.checkUpdates": checkUpdates,
                "general.prefixCopies": prefixCopies,
                "general.appearance": appearance == "dark" ? "dark" : "light",
                "save.automatic": automaticSave,
                "save.intervalMinutes": min(120, max(1, saveInterval)),
                "rythmo.closeReactions": closeReactions,
                "video.showControlAtLaunch": showControlAtLaunch,
                "video.offsetMilliseconds": min(1000, max(-1000, videoOffsetMilliseconds)),
                "rythmo.font": fontName,
                "rythmo.fontSize": fontSize,
                "rythmo.pixelsPerSecond": pixelsPerSecond,
                "rythmo.windowsPixelsPerSecond": pixelsPerSecond,
                "rythmo.height": bandHeight,
                "rythmo.grid": showGrid,
                "rythmo.detection": showDetection
            ]
            do { try WindowsSettings.merge(values) }
            catch { return false }
        }
        #endif
        return true
    }
    public func copyName(for name: String) -> String {
        prefixCopies && !name.hasPrefix("Copie de ") ? "Copie de " + name : name
    }
}
