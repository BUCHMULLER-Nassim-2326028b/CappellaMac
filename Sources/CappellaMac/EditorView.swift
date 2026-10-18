import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CappellaCore

struct EditorView: View {
    @Binding var project: Project
    @StateObject private var transport = Transport()
    @State private var selection: UUID?
    @State private var importingVideo = false
    @State private var query = ""
    @State private var newRoleName = ""
    @State private var error: String?
    @State private var displayProjection = false
    @State private var seekText = "00:00:00:00"
    private var frame: Int { project.mediaStartFrame + Int((transport.seconds * Double(project.framesPerSecond)).rounded(.down)) }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Titre du programme", text: $project.title).font(.title2)
                TextField("Auteur", text: $project.author)
                Picker("Cadence", selection: $project.framesPerSecond) {
                    ForEach([24, 25, 30], id: \.self) { Text("\($0) i/s").tag($0) }
                }
                .disabled(project.originalDetX != nil)
                .help("Timecode non-drop-frame. Changer la cadence conserve les numéros d'images des phrases.")
                Divider()
                Text("Rôles").font(.headline)
                ForEach($project.roles) { $role in
                    HStack {
                        Circle().fill(roleDisplayColor(role)).frame(width: 9, height: 9)
                        TextField("Nom du rôle", text: $role.name)
                        Menu {
                            ForEach(0..<6) { index in
                                Button("Couleur \(index + 1)") {
                                    role.color = index
                                    role.hexColor = ["#0066CC", "#CC2222", "#228833", "#8844AA", "#DD7700", "#0099AA"][index]
                                }
                            }
                            Button("Supprimer le rôle", role: .destructive) { removeRole(role.id) }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).frame(width: 24)
                    }
                }
                HStack {
                    TextField("Nouveau rôle", text: $newRoleName).onSubmit(addRole)
                    Button(action: addRole) { Image(systemName: "plus") }
                        .disabled(newRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                Button("Importer un DetX…", action: importDetX)
                Button("Exporter un DetX…", action: exportDetX).disabled(project.originalDetX == nil)
                Text("\(project.cues.count) phrases · \(project.loops.count) boucles · \(project.shots.count) plans")
                    .font(.caption).foregroundStyle(.secondary)
                Menu("Aller à une boucle") {
                    ForEach(project.loops) { marker in
                        Button("Boucle \(marker.label) · \(Timecode.format(marker.frame, fps: project.framesPerSecond))") { seek(to: marker.frame) }
                    }
                }.disabled(project.loops.isEmpty)
                Spacer()
                Text("Réécriture native · Prototype 0.1\nFormat de travail : .cappellaproject\nDetX : profil 3.7 observé, à valider dans Cappella.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding().frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            VStack(spacing: 0) {
                NativeVideoView(player: transport.player).frame(minHeight: 180, idealHeight: 300)
                HStack {
                    Button("Ouvrir une vidéo…") { importingVideo = true }
                    Text(transport.mediaName).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button { seek(to: frame - 1) } label: { Image(systemName: "backward.frame") }
                    Button("Lecture / Pause") { transport.toggle() }
                    Button { seek(to: frame + 1) } label: { Image(systemName: "forward.frame") }
                    Text(Timecode.format(frame, fps: project.framesPerSecond)).monospacedDigit()
                }.padding(10)
                HStack {
                    Slider(value: Binding(get: { min(transport.seconds, transport.duration) }, set: {
                        transport.seek(frame: Int($0 * Double(project.framesPerSecond)), fps: project.framesPerSecond)
                    }), in: 0...max(0.001, transport.duration))
                    TextField("HH:MM:SS:II", text: $seekText).frame(width: 110).onSubmit(seek)
                    Button("Aller", action: seek)
                }.padding(.horizontal, 10).padding(.bottom, 10)
                RythmoView(project: project, frame: frame).frame(height: 125)
                HStack {
                    TextField("Rechercher un texte ou un rôle", text: $query)
                    Button("Ajouter une phrase", action: addCue)
                    Button("Projection") { displayProjection = true }
                }.padding(10)
                List(selection: $selection) {
                    ForEach(project.cues.filter(matches).sorted { $0.start < $1.start }) { cue in
                        HStack(alignment: .top) {
                            Text(Timecode.format(cue.start, fps: project.framesPerSecond)).monospacedDigit().foregroundStyle(.secondary)
                            Text(roleName(cue.roleID)).foregroundStyle(color(for: cue.roleID)).frame(width: 110, alignment: .leading)
                            Text(cue.text.isEmpty ? "Phrase vide" : cue.text).lineLimit(2)
                        }
                        .tag(cue.id)
                        .contextMenu {
                            Button("Aller à la phrase") { seek(to: cue.start) }
                            Button("Supprimer", role: .destructive) { deleteCue(cue.id) }
                        }
                        .onTapGesture(count: 2) { seek(to: cue.start) }
                    }
                }.frame(minHeight: 110)
                if let index = project.cues.firstIndex(where: { $0.id == selection }) {
                    cueEditor(index: index).padding(10)
                }
            }.frame(minWidth: 730)
        }
        .onAppear { StartupSmokeCheck.recordEditorAppearance() }
        .fileImporter(isPresented: $importingVideo, allowedContentTypes: [.movie, .audio]) { result in
            switch result { case .success(let url): transport.open(url); case .failure(let problem): error = problem.localizedDescription }
        }
        .sheet(isPresented: $displayProjection) {
            VStack {
                RythmoView(project: project, frame: frame).frame(minWidth: 900, minHeight: 240)
                HStack {
                    Button("Lecture / Pause") { transport.toggle() }
                    Button("Fermer") { displayProjection = false }.keyboardShortcut(.cancelAction)
                }.padding()
            }
        }
        .alert("Cappella Mac", isPresented: Binding(get: { error != nil || transport.error != nil }, set: {
            if !$0 { error = nil; transport.error = nil }
        })) { Button("OK") { error = nil; transport.error = nil } } message: { Text(error ?? transport.error ?? "") }
    }

    private func cueEditor(index: Int) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Rôle", selection: $project.cues[index].roleID) {
                    Text("Sans rôle").tag(Optional<UUID>.none)
                    ForEach(project.roles) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 260)
                Picker("Piste", selection: $project.cues[index].track) {
                    ForEach(0..<16) { Text(String($0)).tag($0) }
                }.frame(width: 100)
                Text(Timecode.format(project.cues[index].start, fps: project.framesPerSecond)).monospacedDigit()
                Button("Début ici") {
                    let start = max(0, frame)
                    project.cues[index].start = start
                    project.cues[index].end = max(start + 1, project.cues[index].end)
                }
                Text("→")
                Text(Timecode.format(project.cues[index].end, fps: project.framesPerSecond)).monospacedDigit()
                Button("Fin ici") {
                    guard frame > project.cues[index].start else { error = "La fin doit suivre le début de la phrase."; return }
                    project.cues[index].end = frame
                }
                Spacer()
                Button("Supprimer", role: .destructive) { deleteCue(project.cues[index].id) }
            }
            TextEditor(text: $project.cues[index].text).frame(height: 65).border(.secondary.opacity(0.3))
        }
    }

    private func addCue() {
        let cue = Cue(roleID: project.roles.first?.id, start: max(0, frame), end: max(0, frame) + 3 * project.framesPerSecond)
        project.cues.append(cue); selection = cue.id; query = ""
    }
    private func deleteCue(_ id: UUID) { selection = nil; project.cues.removeAll { $0.id == id } }
    private func addRole() {
        let name = newRoleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !project.roles.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            error = "Ce rôle existe déjà."; return
        }
        project.roles.append(Role(name: name, color: project.roles.count % 6)); newRoleName = ""
    }
    private func removeRole(_ id: UUID) {
        for i in project.cues.indices where project.cues[i].roleID == id { project.cues[i].roleID = nil }
        project.roles.removeAll { $0.id == id }
    }
    private func roleName(_ id: UUID?) -> String { project.roles.first { $0.id == id }?.name ?? "Sans rôle" }
    private func color(for id: UUID?) -> Color {
        project.roles.first { $0.id == id }.map(roleDisplayColor) ?? .primary
    }
    private func matches(_ cue: Cue) -> Bool {
        query.isEmpty || cue.text.localizedCaseInsensitiveContains(query) || roleName(cue.roleID).localizedCaseInsensitiveContains(query)
    }
    private func seek() {
        guard let target = Timecode.parse(seekText, fps: project.framesPerSecond) else { error = "Timecode invalide : HH:MM:SS:II."; return }
        seek(to: target)
    }
    private func seek(to target: Int) { transport.seek(frame: target - project.mediaStartFrame, fps: project.framesPerSecond) }

    private func importDetX() {
        if !project.cues.isEmpty || !project.roles.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remplacer le contenu du document courant ?"
            alert.informativeText = "Enregistrez votre travail avant l'import. Le fichier DetX sélectionné ne sera pas modifié."
            alert.addButton(withTitle: "Annuler"); alert.addButton(withTitle: "Remplacer")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.detx, .xml]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try DetX.read(Data(contentsOf: url), fps: project.framesPerSecond)
            transport.player.pause()
            selection = nil; project = imported; query = ""
            seekText = Timecode.format(imported.mediaStartFrame, fps: imported.framesPerSecond)
            transport.seek(frame: 0, fps: project.framesPerSecond)
        } catch { self.error = error.localizedDescription }
    }

    private func exportDetX() {
        do {
            let data = try DetX.write(project)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.detx]
            panel.nameFieldStringValue = "Adaptation-Mac.detx"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
}

func roleColor(_ index: Int) -> Color {
    let colors: [Color] = [.blue, .red, .green, .purple, .orange, .cyan]
    return colors[((index % colors.count) + colors.count) % colors.count]
}

func roleDisplayColor(_ role: Role) -> Color {
    if let hex = role.hexColor, hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) {
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
    return roleColor(role.color)
}

struct RythmoView: View {
    var project: Project
    var frame: Int
    var body: some View {
        Canvas { context, size in
            let cursor = size.width * 0.22
            let pixelsPerFrame = 100.0 / Double(project.framesPerSecond)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            for row in 1...3 {
                var line = Path(); let y = Double(row) * size.height / 4
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.gray.opacity(0.25)), lineWidth: 1)
            }
            // Début et durée de phrase ; alignement labial détaillé à implémenter.
            let lanes = max(4, (project.cues.map(\.track).max() ?? 0) + 1)
            for cue in project.cues {
                let x = cursor + Double(cue.start - frame) * pixelsPerFrame
                let end = cursor + Double(cue.end - frame) * pixelsPerFrame
                guard end >= 0, x <= size.width else { continue }
                let role = project.roles.first { $0.id == cue.roleID }
                let y = Double(cue.track + 1) * size.height / Double(lanes + 1)
                let color = role.map(roleDisplayColor) ?? .black
                let label = Text(cue.text).font(.system(size: 23, weight: .medium)).foregroundColor(color)
                context.draw(label, at: CGPoint(x: x, y: y), anchor: .leading)
                var interval = Path(); interval.move(to: CGPoint(x: x, y: y + 15)); interval.addLine(to: CGPoint(x: end, y: y + 15))
                context.stroke(interval, with: .color(color.opacity(0.45)), lineWidth: 2)
            }
            var bar = Path(); bar.move(to: CGPoint(x: cursor, y: 0)); bar.addLine(to: CGPoint(x: cursor, y: size.height))
            context.stroke(bar, with: .color(.red), lineWidth: 2)
        }
        .accessibilityLabel("Bande rythmo au timecode \(Timecode.format(frame, fps: project.framesPerSecond))")
    }
}
