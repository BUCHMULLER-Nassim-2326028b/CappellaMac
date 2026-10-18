import SwiftUI
import AppKit
import CappellaCore

/// The chooser and role inspector use the same portrait data, so changing the
/// selected role or replacing its image cannot leave the previous face behind.
struct RolePortrait: View {
    var role: Role?
    var size: CGFloat = 128

    var body: some View {
        Group {
            if let data = role?.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.square").font(.system(size: 36)).accessibilityHidden(true)
                    Text(role?.imageData == nil ? "Aucun portrait" : "Portrait illisible")
                        .font(.caption).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(role.map { "Portrait de \($0.name)" } ?? "Portrait du rôle")
    }
}
