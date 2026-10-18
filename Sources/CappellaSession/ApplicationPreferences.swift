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
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        func number(_ key: String, _ fallback: Double) -> Double {
            guard defaults.object(forKey: key) != nil else { return fallback }
            let value = defaults.double(forKey: key)
            return value.isFinite ? value : fallback
        }
        value.checkUpdates = bool("general.checkUpdates", false)
        value.prefixCopies = bool("general.prefixCopies", true)
        value.appearance = defaults.string(forKey: "general.appearance") == "dark" ? "dark" : "light"
        value.automaticSave = bool("save.automatic", true)
        value.saveInterval = Int(min(120, max(1, number("save.intervalMinutes", 5))))
        value.closeReactions = bool("rythmo.closeReactions", false)
        value.showControlAtLaunch = bool("video.showControlAtLaunch", false)
        value.videoOffsetMilliseconds = min(1000, max(-1000, number("video.offsetMilliseconds", 0)))
        value.fontName = defaults.string(forKey: "rythmo.font") ?? value.fontName
        value.fontSize = number("rythmo.fontSize", 28)
        value.pixelsPerSecond = number("rythmo.pixelsPerSecond", 120)
        value.bandHeight = number("rythmo.height", 146)
        value.showGrid = bool("rythmo.grid", true)
        value.showDetection = bool("rythmo.detection", true)
        return value
    }
    public func save(to defaults: UserDefaults = .standard) {
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
        defaults.set(bandHeight, forKey: "rythmo.height")
        defaults.set(showGrid, forKey: "rythmo.grid")
        defaults.set(showDetection, forKey: "rythmo.detection")
    }
    public func copyName(for name: String) -> String {
        prefixCopies && !name.hasPrefix("Copie de ") ? "Copie de " + name : name
    }
}
