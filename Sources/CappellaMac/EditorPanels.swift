import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore

struct RolesPanel: View {
    @Binding var project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var error: String?
    var body: some View {
        VStack {
            HSplitView {
                VStack {
                    List(selection: $selected) {
                        ForEach(project.roles) { role in
                            HStack { Circle().fill(roleDisplayColor(role)).frame(width: 9, height: 9); Text(role.name) }.tag(role.id)
                        }
                    }
                    HStack {
                        Button("Ajouter") {
                            var number = project.roles.count + 1
                            while project.roles.contains(where: { $0.name == "Rôle \(number)" }) { number += 1 }
                            let role = Role(name: "Rôle \(number)", color: project.roles.count % 6)
                            project.roles.append(role); selected = role.id
                        }
                        Button("Supprimer", role: .destructive) { project.roles.removeAll { $0.id == selected }; selected = nil }
                            .disabled(selected == nil || project.cues.contains { $0.roleID == selected })
                    }.padding(8)
                }.frame(minWidth: 200)
                if let index = project.roles.firstIndex(where: { $0.id == selected }) {
                    RoleInspector(role: $project.roles[index]).padding().frame(minWidth: 300)
                } else { Text("Sélectionner un rôle").foregroundStyle(.secondary).frame(width: 320) }
            }
            HStack {
                Text("Un rôle attribué à une phrase ne peut pas être supprimé.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Fermer") {
                    do { try project.validate(); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 650, height: 470)
        .alert("Rôles", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private struct RoleInspector: View {
    @Binding var role: Role
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Nom", text: $role.name)
            ColorPicker("Couleur", selection: Binding(get: { roleDisplayColor(role) }, set: { value in
                if let rgb = NSColor(value).usingColorSpace(.sRGB) {
                    role.hexColor = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                }
            }), supportsOpacity: false)
            Picker("Genre", selection: Binding(get: { role.gender ?? "neutral" }, set: { role.gender = $0 })) {
                Text("Neutre").tag("neutral"); Text("Masculin").tag("male"); Text("Féminin").tag("female")
            }
            Text("Description")
            TextEditor(text: Binding(get: { role.descriptionText ?? "" }, set: { role.descriptionText = $0 })).frame(height: 95)
            if let data = role.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 110)
            }
            Button("Choisir un portrait…") {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 5_000_000, let image = NSImage(data: data),
                          let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                        throw ProjectError.invalid("Choisir une image valide de moins de 5 Mo.")
                    }
                    role.imageData = jpeg
                } catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
    }
}

struct PropertiesPanel: View {
    @Binding var project: Project
    @Environment(\.dismiss) private var dismiss
    private func metadata(_ key: String) -> Binding<String> {
        Binding(get: { project.metadata?[key] ?? "" }, set: {
            if project.metadata == nil { project.metadata = [:] }
            project.metadata?[key] = $0
        })
    }
    var body: some View {
        VStack {
            TabView {
                Form {
                    TextField("Titre original", text: $project.title)
                    TextField("Titre français", text: metadata("title2"))
                    TextField("Épisode", text: metadata("episode.number"))
                    TextField("Saison", text: metadata("episode.season"))
                    TextField("Titre de l'épisode", text: metadata("episode.title"))
                    TextField("Titre français de l'épisode", text: metadata("episode.title2"))
                    TextField("Auteur", text: $project.author)
                    TextField("Second auteur — prénom", text: metadata("second-author.firstname"))
                    TextField("Second auteur — nom", text: metadata("second-author.name"))
                    TextField("Détecteur — prénom", text: metadata("detector.firstname"))
                    TextField("Détecteur — nom", text: metadata("detector.name"))
                    Picker("Cadence", selection: $project.framesPerSecond) {
                        ForEach([24, 25, 30], id: \.self) { Text("\($0) i/s").tag($0) }
                    }.disabled(!project.cues.isEmpty || project.originalDetX != nil)
                }.padding().tabItem { Text("Programme") }
                Form {
                    TextField("Année", text: metadata("production.year"))
                    TextField("Pays", text: metadata("production.country"))
                    TextField("Réalisateur", text: metadata("production.director"))
                    TextField("Producteur", text: metadata("production.producer"))
                    TextField("Distributeur", text: metadata("production.distributor"))
                    TextField("Diffuseur", text: metadata("production.diffuser"))
                    TextField("Acteurs principaux", text: metadata("production.actors"))
                    Text("Résumé"); TextEditor(text: metadata("summary")).frame(height: 130)
                    Text("Notes"); TextEditor(text: metadata("notes")).frame(height: 85)
                }.padding().tabItem { Text("Production") }
                VStack {
                    Text("Boucles").font(.headline)
                    List {
                        ForEach($project.loops) { $marker in
                            HStack {
                                MarkerRow(marker: $marker, fps: project.framesPerSecond)
                                Button("Supprimer", role: .destructive) { project.loops.removeAll { $0.id == marker.id } }
                            }
                        }
                    }
                    Text("Changements de plan").font(.headline)
                    List {
                        ForEach($project.shots) { $marker in
                            HStack {
                                MarkerRow(marker: $marker, fps: project.framesPerSecond)
                                Button("Supprimer", role: .destructive) { project.shots.removeAll { $0.id == marker.id } }
                            }
                        }
                    }
                }.padding().tabItem { Text("Repères") }
            }
            HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }.frame(width: 660, height: 570)
    }
}

private struct MarkerRow: View {
    @Binding var marker: Marker
    var fps: Int
    @State private var text = ""
    var body: some View {
        HStack {
            TextField("Numéro", text: $marker.label).frame(width: 80)
            TextField("Timecode", text: $text).monospacedDigit().onSubmit {
                if let value = Timecode.parse(text, fps: fps) { marker.frame = value }
                text = Timecode.format(marker.frame, fps: fps)
            }.onChange(of: text) { value in if let frame = Timecode.parse(value, fps: fps) { marker.frame = frame } }
        }.onAppear { text = Timecode.format(marker.frame, fps: fps) }
    }
}

struct RoleImportPanel: View {
    @Binding var project: Project
    var candidates: [Role]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    private func exists(_ role: Role) -> Bool {
        project.roles.contains { $0.name.localizedCaseInsensitiveCompare(role.name) == .orderedSame }
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text("Rôles à importer").font(.headline)
            List(candidates) { role in
                Toggle(role.name, isOn: Binding(get: { selected.contains(role.id) }, set: {
                    if $0 { selected.insert(role.id) } else { selected.remove(role.id) }
                })).disabled(exists(role))
            }
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Importer") {
                    for candidate in candidates where selected.contains(candidate.id) && !exists(candidate) {
                        var role = candidate; role.id = UUID(); role.sourceID = nil; project.roles.append(role)
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
            }
        }.padding(20).frame(width: 450, height: 430)
        .onAppear { selected = Set(candidates.filter { !exists($0) }.map(\.id)) }
    }
}

/// Exposes the insertion position in characters to anchor a lipsync sign to text.
struct DialogueTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var caret: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let view = FocusedTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 70)); view.isRichText = false; view.allowsUndo = true
        view.font = NSFont(name: "Courier New", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.minSize = NSSize(width: 0, height: 70)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.string = text; view.delegate = context.coordinator; scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            context.coordinator.updating = true; view.string = text; context.coordinator.updating = false
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DialogueTextEditor
        var updating = false
        init(_ parent: DialogueTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? NSTextView,
                  let range = Range(NSRange(location: 0, length: view.selectedRange().location), in: view.string) else { return }
            parent.caret = view.string[range].unicodeScalars.count
        }
    }
    final class FocusedTextView: NSTextView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.window?.makeFirstResponder(self)
            }
        }
    }
}

func roleColor(_ index: Int) -> Color {
    let colors: [Color] = [.blue, .red, .green, .purple, .orange, .cyan]
    return colors[((index % colors.count) + colors.count) % colors.count]
}
func roleDisplayColor(_ role: Role) -> Color {
    if let hex = role.hexColor, hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) {
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
    return roleColor(role.color)
}
