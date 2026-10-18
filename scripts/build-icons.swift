import AppKit
import Foundation

/// Convert the supplied transparent logos into a full macOS icon set without
/// cropping or stretching the artwork. iconutil packages the PNG sizes later.
@main
struct BuildIcons {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw failure("Arguments : logo-clair.png logo-sombre.png dossier-sortie")
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (argument, name) in [(1, "AppIcon"), (2, "AppIconDark")] {
            guard let image = NSImage(contentsOfFile: CommandLine.arguments[argument]), image.size.width > 0, image.size.height > 0 else {
                throw failure("Logo absent ou illisible : \(CommandLine.arguments[argument])")
            }
            let iconset = destination.appendingPathComponent(name + ".iconset", isDirectory: true)
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for points in [16, 32, 128, 256, 512] {
                for factor in [1, 2] {
                    let pixels = points * factor
                    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Création de l'icône impossible.") }
                    let side = CGFloat(pixels)
                    context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
                    context.imageInterpolation = .high
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    let scale = side * 0.875 / max(image.size.width, image.size.height)
                    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Encodage PNG impossible.") }
                    let suffix = factor == 2 ? "@2x" : ""
                    let url = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                    try data.write(to: url)
                }
            }
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CappellaIconBuild", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
