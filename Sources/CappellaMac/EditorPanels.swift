import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore
import CappellaSession

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
                    ScrollView {
                        RoleInspector(role: $project.roles[index]).padding()
                    }.frame(minWidth: 300)
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
        .onAppear { if selected == nil { selected = project.roles.first?.id } }
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
            HStack { Spacer(); RolePortrait(role: role); Spacer() }
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
    @Binding var source: Project
    @State private var project: Project
    var applyFiles: (Project) -> Void
    @State private var fileError: String?
    init(project: Binding<Project>, applyFiles: @escaping (Project) -> Void) {
        _source = project; _project = State(initialValue: project.wrappedValue); self.applyFiles = applyFiles
    }
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
                VStack(spacing: 18) {
                    fileRow("Image", value: project.videoPath ?? "", browse: { chooseFile(0) })
                    fileRow("Son", value: project.audioPath ?? "", browse: { chooseFile(1) })
                    fileRow("Liste des rôles", value: project.metadata?["roles-file"] ?? "", browse: { chooseFile(2) })
                    Spacer()
                }.padding(24).tabItem { Text("Fichier") }
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

                }.padding().tabItem { Text("Production") }
                Form {
                    Text("Résumé"); TextEditor(text: metadata("summary")).frame(height: 160)
                    Text("Notes"); TextEditor(text: metadata("notes")).frame(height: 160)
                }.padding().tabItem { Text("Description") }
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
            HStack {
                Spacer()
                Button("OK") { apply(); if fileError == nil { dismiss() } }.keyboardShortcut(.defaultAction)
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Appliquer", action: apply).disabled(source == project)
            }.padding()
        }.frame(width: 700, height: 570)
        .alert("Propriétés", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK") { fileError = nil }
        } message: { Text(fileError ?? "") }
    }
    private func apply() {
        do { try project.validate(); let old = source; source = project; fileError = nil; applyFiles(old) }
        catch { fileError = error.localizedDescription }
    }
    private func chooseFile(_ kind: Int) {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = false
        picker.allowedContentTypes = kind == 0 ? [.movie] : kind == 1 ? [.audio] : [.detx, .xml]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        if kind == 0 { project.videoPath = url.path }
        else if kind == 1 { project.audioPath = url.path }
        else {
            do {
                let imported = try DetX.read(Data(contentsOf: url), fps: project.framesPerSecond)
                for candidate in imported.roles where !project.roles.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate.name) == .orderedSame }) {
                    var role = candidate; role.id = UUID(); role.sourceID = nil; project.roles.append(role)
                }
                if project.metadata == nil { project.metadata = [:] }; project.metadata?["roles-file"] = url.path
            } catch { fileError = error.localizedDescription }
        }
    }
    private func fileRow(_ label: String, value: String, browse: @escaping () -> Void) -> some View {
        HStack {
            Text(label + " :").frame(width: 95, alignment: .trailing)
            TextField("", text: .constant(value)).disabled(true)
            Button("Parcourir…", action: browse)
        }
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
