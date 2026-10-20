import Foundation

/// Logical channels follow the file order, independently of container tracks.
public enum AudioRouting {
    public static func versions(total: Int) -> [[Int]] {
        let original = selectedChannels(total: total, international: false)
        let international = selectedChannels(total: total, international: true)
        return international.isEmpty ? [original] : [original, international]
    }
    public static func selectedChannels(total: Int, international: Bool) -> [Int] {
        switch total {
        case 4: return international ? [2, 3] : [0, 1]
        case 2: return international ? [1] : [0]
        default: return international ? [] : Array(0..<max(0, total))
        }
    }
}
