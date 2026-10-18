import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import CappellaCore

private enum EditorPanel: String, Identifiable {
    case roles, importRoles, properties, find, timecode, shift, timestamp, positions, preferences, validation
    var id: String { rawValue }
}

@MainActor
struct EditorView: View {
    @Binding var project: Project
    @StateObject private var transport = Transport()
    @StateObject private var projection = ProjectionController()
    @State private var selection: UUID?
    @State private var selectedSign: UUID?
    @State private var editingPhrase = false
    @State private var currentTrack = 0
    @State private var caret = 0
    @State private var detectionMode = false
    @State private var panel: EditorPanel?
    @State private var query = ""
    @State private var searchRole: UUID?
    @State private var wholeWords = false
    @State private var exactCase = false
    @State private var input = ""
    @State private var error: String?
    @State private var validationReport = ""
    @State private var lastScrolledCue: UUID?
    @State private var rolesToImport: [Role] = []
    @AppStorage("rythmo.pixelsPerSecond") private var pixelsPerSecond = 120.0
    @AppStorage("rythmo.font") private var fontName = "Apple Chancery"
    @AppStorage("rythmo.fontSize") private var fontSize = 28.0
    @AppStorage("rythmo.height") private var rythmoHeight = 146.0
    @AppStorage("rythmo.grid") private var showGrid = true
    @AppStorage("rythmo.detection") private var showDetection = true
    private var frame: Int { project.mediaStartFrame + Int((transport.seconds * Double(project.framesPerSecond)).rounded(.down)) }
    private var selectedCue: Cue? { project.cues.first { $0.id == selection } }
    private var orderedCues: [Cue] { project.cues.sorted { $0.start == $1.start ? $0.track < $1.track : $0.start < $1.start } }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HSplitView {
                    VStack(spacing: 0) {
                        scriptPane
                        if editingPhrase, let cue = selectedCue { phraseEditor(cue).padding(8).background(Color(white: 0.94)) }
                        cartouche
                    }
                    .frame(minWidth: 310, idealWidth: geometry.size.width * 0.445, maxWidth: .infinity, maxHeight: .infinity)
                    videoPane.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                }
                RythmoView(project: project, frame: frame, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize,
                           showGrid: showGrid, showDetection: showDetection, selectedSign: selectedSign,
                           seek: { target, track in
                               currentTrack = track; selectedSign = nil; seek(to: target)
                               if let cue = project.cues.last(where: { $0.track == track && $0.start <= target && $0.end >= target }) { selection = cue.id }
                           }, moveSign: moveSign)
                    .frame(height: rythmoHeight)
            }
        }
        .background(Color(white: 0.965))
        .preferredColorScheme(.light)
        .background(EditorKeyboardMonitor(perform: perform).frame(width: 0, height: 0))
        .focusedSceneValue(\.editorActions, EditorActions(perform: perform, hasSelection: selection != nil, hasSign: selectedSign != nil,
                                                        showGrid: showGrid, showDetection: showDetection, detectionMode: detectionMode))
        .onAppear {
            for index in project.cues.indices where project.cues[index].signs == nil { project.cues[index].signs = project.cues[index].anchors }
            if let position = project.lastPositionFrame { seek(to: position) }
            StartupSmokeCheck.recordEditorAppearance(cueCount: project.cues.count)
        }
        .onDisappear { transport.setRate(0); projection.close() }
        .sheet(item: $panel) { activePanel in panelView(activePanel) }
        .alert("Cappella", isPresented: Binding(get: { error != nil || transport.error != nil }, set: {
            if !$0 { error = nil; transport.error = nil }
        })) { Button("OK") { error = nil; transport.error = nil } } message: { Text(error ?? transport.error ?? "") }
    }

    private var scriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(orderedCues) { cue in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(Timecode.format(cue.start, fps: project.framesPerSecond)).font(.custom("Courier New", size: 9))
                                Text("- \(roleName(cue.roleID)) :").font(.custom("Courier New", size: 12).weight(.bold))
                            }
                            Text(cue.text).font(.custom("Courier New", size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.14))
                        .padding(.vertical, 2).padding(.horizontal, 8)
                        .background(selection == cue.id ? Color.blue.opacity(0.08) : Color.clear)
                        .contentShape(Rectangle()).id(cue.id)
                        .onTapGesture(count: 2) { select(cue, edit: true) }
                        .onTapGesture { select(cue, edit: false) }
                        .contextMenu {
                            Button("Modifier la phrase") { select(cue, edit: true) }
                            Menu("Changer de piste") {
                                ForEach(0..<4) { track in Button("Piste \(track + 1)") { selection = cue.id; perform(.track(track)) } }
                            }
                            Button("Voix off") { selection = cue.id; perform(.voiceOff) }
                            Button("Supprimer", role: .destructive) { selection = cue.id; perform(.deletePhrase) }
                        }
                    }
                }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(red: 0.965, green: 0.968, blue: 0.977))
            .onChange(of: selection) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: frame) { value in
                guard transport.rate != 0, !editingPhrase,
                      let cue = orderedCues.last(where: { $0.start <= value }), cue.id != lastScrolledCue else { return }
                lastScrolledCue = cue.id; proxy.scrollTo(cue.id, anchor: .center)
            }
        }
    }

    private var videoPane: some View {
        ZStack {
            Color.white
            if transport.mediaName != nil {
                NativeVideoView(player: transport.player)
            } else if let image = Self.mire {
                GeometryReader { geometry in
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
        .contextMenu { Button("Ouvrir l'image…") { perform(.openMedia) } }
    }
    private static let mire = Bundle.main.url(forResource: "Mire", withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }

    private var cartouche: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("timecode").font(.system(size: 10))
                        Text(Timecode.format(frame, fps: project.framesPerSecond)).font(.system(size: 28, weight: .light)).monospacedDigit()
                    }.onTapGesture { perform(.goTimecode) }
                    if let loop = currentLoop {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("boucle").font(.system(size: 10)); Text(loop.marker.label).font(.system(size: 20, weight: .light))
                            Text("     durée").font(.system(size: 10))
                            Text("\(loop.duration / (project.framesPerSecond * 60))").font(.system(size: 20, weight: .light))
                            Text("min").font(.system(size: 10))
                            Text("\((loop.duration / project.framesPerSecond) % 60)").font(.system(size: 20, weight: .light))
                            Text("s").font(.system(size: 10))
                        }
                    } else { Spacer(minLength: 0) }
                    HStack {
                        if let loop = currentLoop {
                            Text("\(Timecode.format(loop.marker.frame, fps: project.framesPerSecond)) → \(Timecode.format(loop.end, fps: project.framesPerSecond))")
                        }
                        Spacer()
                        Button("VO") { if transport.usingVI { transport.toggleVI() } }.foregroundColor(!transport.usingVI ? .white : .gray)
                        Button("VI") { if !transport.usingVI { transport.toggleVI() } }.foregroundColor(transport.usingVI ? .white : .gray)
                        Spacer()
                    }.font(.system(size: 10)).foregroundStyle(Color(red: 0.43, green: 0.53, blue: 0.59)).buttonStyle(.plain)
                }
                .padding(.horizontal, 7).padding(.vertical, 7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white).background(Color(red: 0.14, green: 0.17, blue: 0.20))
                Color(white: 0.93).frame(width: geometry.size.width * 0.19)
            }
        }.frame(height: 92).overlay(alignment: .top) { Rectangle().fill(Color.gray).frame(height: 0.5) }
    }

    private var currentLoop: (marker: Marker, end: Int, duration: Int)? {
        let loops = project.loops.sorted { $0.frame < $1.frame }
        guard let index = loops.lastIndex(where: { $0.frame <= frame }) else { return nil }
        let end = index + 1 < loops.count ? loops[index + 1].frame : max(project.cues.map(\.end).max() ?? loops[index].frame, project.mediaStartFrame + Int(transport.duration * Double(project.framesPerSecond)))
        return (loops[index], end, max(0, end - loops[index].frame))
    }

    private func phraseEditor(_ cue: Cue) -> some View {
        VStack(spacing: 5) {
            HStack {
                Picker("Rôle", selection: Binding(get: { selectedCue?.roleID }, set: { value in mutateSelected { $0.roleID = value } })) {
                    Text("Sans rôle").tag(Optional<UUID>.none)
                    ForEach(project.roles) { Text($0.name).tag(Optional($0.id)) }
                }.labelsHidden()
                Picker("Piste", selection: Binding(get: { selectedCue?.track ?? 0 }, set: { value in mutateSelected { $0.track = value }; currentTrack = value })) {
                    ForEach(0..<4) { Text("Piste \($0 + 1)").tag($0) }
                }.labelsHidden().frame(width: 85)
                Button { editingPhrase = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            DialogueTextEditor(text: Binding(get: { project.cues.first { $0.id == cue.id }?.text ?? "" }, set: { value in
                if let index = project.cues.firstIndex(where: { $0.id == cue.id }) { project.cues[index].replaceText(value) }
            }), caret: $caret).frame(height: 70).id(cue.id)
            HStack {
                Text(Timecode.format(cue.start, fps: project.framesPerSecond)).monospacedDigit()
                Button("Début ici") { setBoundary(start: true, kind: nil) }
                Spacer()
                Text(Timecode.format(cue.end, fps: project.framesPerSecond)).monospacedDigit()
                Button("Fin ici") { setBoundary(start: false, kind: nil) }
            }.font(.system(size: 10))
        }
    }

    @ViewBuilder private func panelView(_ active: EditorPanel) -> some View {
        switch active {
        case .roles: RolesPanel(project: $project)
        case .importRoles: RoleImportPanel(project: $project, candidates: rolesToImport)
        case .properties: PropertiesPanel(project: $project)
        case .find:
            VStack(alignment: .leading, spacing: 14) {
                Text("Rechercher").font(.headline)
                TextField("Texte", text: $query).onSubmit(findNext)
                Picker("Rôle", selection: $searchRole) {
                    Text("Tous les rôles").tag(Optional<UUID>.none)
                    ForEach(project.roles) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Mots entiers", isOn: $wholeWords); Toggle("Respecter la casse", isOn: $exactCase)
                HStack { Button("Fermer") { panel = nil }; Spacer(); Button("Suivant", action: findNext).keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width: 410)
        case .timecode, .timestamp, .shift:
            VStack(alignment: .leading, spacing: 16) {
                Text(active == .timecode ? "Aller au timecode" : active == .timestamp ? "Timestamp de l'image" : "Décaler la rythmo").font(.headline)
                TextField(active == .shift ? "Décalage en images (+ ou −)" : "HH:MM:SS:II", text: $input).onSubmit(applyInput)
                if active == .timestamp { Text("Les phrases, signes, boucles et plans sont décalés avec l'origine vidéo.").font(.caption) }
                HStack { Button("Annuler") { panel = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Appliquer", action: applyInput).keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width: 420)
        case .positions:
            VStack {
                Text("Positions mémorisées").font(.headline)
                List(project.positions ?? []) { marker in
                    HStack {
                        Button("\(Timecode.format(marker.frame, fps: project.framesPerSecond)) — \(marker.label)") { seek(to: marker.frame); panel = nil }.buttonStyle(.plain)
                        Spacer(); Button("Supprimer", role: .destructive) { project.positions?.removeAll { $0.id == marker.id } }
                    }
                }
                Button("Fermer") { panel = nil }.keyboardShortcut(.cancelAction)
            }.padding().frame(width: 500, height: 340)
        case .preferences:
            VStack(alignment: .leading, spacing: 18) {
                Text("Bande rythmo").font(.headline)
                Picker("Police", selection: $fontName) {
                    ForEach(["Apple Chancery", "Snell Roundhand", "Times New Roman", "Arial", "Courier New"], id: \.self) { Text($0).tag($0) }
                }
                HStack { Text("Taille"); Slider(value: $fontSize, in: 16...42); Text("\(Int(fontSize))") }
                HStack { Text("Vitesse de défilement"); Slider(value: $pixelsPerSecond, in: 30...400) }
                HStack { Text("Hauteur"); Slider(value: $rythmoHeight, in: 120...260) }
                Toggle("Grille et signes", isOn: $showGrid); Toggle("Détection", isOn: $showDetection)
                Button("Fermer") { panel = nil }.keyboardShortcut(.defaultAction)
            }.padding(20).frame(width: 480)
        case .validation:
            VStack {
                Text("Vérification de la rythmo").font(.headline)
                ScrollView { Text(validationReport).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Fermer") { panel = nil }.keyboardShortcut(.defaultAction)
            }.padding(20).frame(width: 580, height: 380)
        }
    }

    private func perform(_ action: EditorAction) {
        switch action {
        case .openMedia: chooseMedia(audio: false)
        case .openVI: chooseMedia(audio: true)
        case .importDetX: importDetX()
        case .importRoles:
            let picker = NSOpenPanel(); picker.allowedContentTypes = [.detx, .xml]
            guard picker.runModal() == .OK, let url = picker.url else { return }
            do { rolesToImport = try DetX.read(Data(contentsOf: url), fps: project.framesPerSecond).roles; panel = .importRoles }
            catch { self.error = error.localizedDescription }
        case .exportDetX: exportData(type: .detx, name: "\(project.title).detx") { try DetX.write(project) }
        case .exportScript:
            exportData(type: .rtf, name: "Script.rtf") {
                let text = NSAttributedString(string: project.scriptText(), attributes: [.font: NSFont(name: "Courier New", size: 12) ?? NSFont.systemFont(ofSize: 12)])
                return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }
        case .exportCrossTable: exportData(type: .commaSeparatedText, name: "Croisille.csv") { Data(project.crossTableCSV().utf8) }
        case .roles: panel = .roles
        case .properties: panel = .properties
        case .find: panel = .find
        case .goTimecode: input = Timecode.format(frame, fps: project.framesPerSecond); panel = .timecode
        case .shift: input = "0"; panel = .shift
        case .timestamp: input = Timecode.format(project.mediaStartFrame, fps: project.framesPerSecond); panel = .timestamp
        case .preferences: panel = .preferences
        case .check: verify()
        case .playPause: transport.toggle()
        case .stop: transport.setRate(0); project.lastPositionFrame = frame
        case .step(let amount): transport.setRate(0); seek(to: frame + amount)
        case .rate(let value): transport.setRate(value)
        case .navigate(let type, let direction): navigate(type, direction: direction)
        case .addPhrase: addPhrase(kind: "in_open")
        case .deletePhrase:
            if let id = selection { project.cues.removeAll { $0.id == id } }
            selection = nil; selectedSign = nil; editingPhrase = false
        case .track(let value): currentTrack = value; mutateSelected { $0.track = value }
        case .mode:
            detectionMode.toggle()
            if detectionMode { addPhrase(kind: "in_open") }
            else if selectedCue != nil { setBoundary(start: false, kind: "out_open") }
        case .addSign(let kind): addSign(kind)
        case .deleteSign:
            guard let cue = selectedCue, let id = selectedSign, let index = cue.anchors.firstIndex(where: { $0.id == id }) else { return }
            guard index > 0, index < cue.anchors.count - 1 else { error = "Les signes de début et de fin délimitent la phrase. Supprimez la phrase pour les retirer."; return }
            mutateSelected { $0.signs?.removeAll { $0.id == id } }; selectedSign = nil
        case .shiftSign(let amount):
            if let cue = selectedCue, let sign = cue.anchors.first(where: { $0.id == selectedSign }) { moveSign(cue.id, sign.id, sign.frame + amount) }
        case .voiceOff: mutateSelected { $0.voice = $0.voice == "off" ? nil : "off" }
        case .addLoop:
            guard !project.loops.contains(where: { $0.frame == frame }) else { return }
            project.loops.append(Marker(frame: frame, label: String(project.loops.count + 1)))
            project.loops.sort { $0.frame < $1.frame }
            for i in project.loops.indices { project.loops[i].label = String(i + 1) }
        case .addShot:
            if !project.shots.contains(where: { $0.frame == frame }) { project.shots.append(Marker(frame: frame, label: String(project.shots.count + 1))) }
        case .markPosition:
            if let label = prompt("Marquer cette position", initial: "Position \((project.positions?.count ?? 0) + 1)") {
                if project.positions == nil { project.positions = [] }
                project.positions?.append(Marker(frame: frame, label: label))
            }
        case .positions: panel = .positions
        case .zoom(let factor): pixelsPerSecond = min(800, max(15, pixelsPerSecond * factor))
        case .grid: showGrid.toggle()
        case .detection: showDetection.toggle()
        case .fullScreen: NSApplication.shared.keyWindow?.toggleFullScreen(nil)
        case .projection: projection.show(project: $project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
        case .toggleVI: transport.toggleVI()
        case .mute: transport.toggleMute()
        case .volume(let delta): transport.changeVolume(delta)
        }
    }

    private func mutateSelected(_ change: (inout Cue) -> Void) {
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        change(&project.cues[index])
    }
    private func roleName(_ id: UUID?) -> String { project.roles.first { $0.id == id }?.name ?? "Sans rôle" }
    private func seek(to target: Int) {
        let value = max(project.mediaStartFrame, target)
        transport.seek(frame: value - project.mediaStartFrame, fps: project.framesPerSecond)
    }
    private func select(_ cue: Cue, edit: Bool) {
        selection = cue.id; currentTrack = cue.track; selectedSign = nil
        seek(to: cue.start)
        if edit { editingPhrase = true; caret = 0 }
    }
    private func addPhrase(kind: String) {
        guard let role = selectedCue?.roleID ?? project.roles.first?.id else { panel = .roles; return }
        var cue = Cue(roleID: role, start: frame, end: frame + 3 * project.framesPerSecond)
        cue.track = currentTrack; cue.signs = cue.anchors; cue.signs?[0].kind = kind
        project.cues.append(cue); selection = cue.id; editingPhrase = true; caret = 0; selectedSign = nil
    }
    private func setBoundary(start: Bool, kind: String?) {
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        do {
            try project.cues[index].setBounds(start: start ? frame : project.cues[index].start, end: start ? project.cues[index].end : frame)
            if let kind {
                var signs = project.cues[index].anchors
                signs[start ? 0 : signs.count - 1].kind = kind; project.cues[index].signs = signs
            }
        } catch { self.error = error.localizedDescription }
    }
    private func addSign(_ kind: String) {
        if kind.hasPrefix("in_") { addPhrase(kind: kind); return }
        if kind.hasPrefix("out_") { setBoundary(start: false, kind: kind); return }
        guard let index = project.cues.firstIndex(where: { $0.id == selection }) else { return }
        do {
            let offset = editingPhrase ? min(caret, project.cues[index].text.unicodeScalars.count) : Timeline.textOffset(in: project.cues[index], at: frame)
            try Timeline.addSign(to: &project.cues[index], kind: kind, frame: frame, textOffset: offset)
            selectedSign = project.cues[index].signs?.first { $0.frame == frame && $0.kind == kind }?.id
        } catch { self.error = error.localizedDescription }
    }
    private func moveSign(_ cueID: UUID, _ signID: UUID, _ target: Int) {
        guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else { return }
        selection = cueID; selectedSign = signID
        Timeline.moveSign(in: &project.cues[index], id: signID, to: target)
    }
    private func navigate(_ type: String, direction: Int) {
        let targets: [Int]
        switch type {
        case "loop": targets = project.loops.map(\.frame)
        case "shot": targets = project.shots.map(\.frame)
        case "sign": targets = project.cues.flatMap { $0.anchors.map(\.frame) }
        case "role": targets = project.cues.filter { $0.roleID == selectedCue?.roleID }.map(\.start)
        default: targets = project.cues.map(\.start)
        }
        let target = direction > 0 ? targets.filter { $0 > frame }.min() : targets.filter { $0 < frame }.max()
        guard let target else { return }
        seek(to: target)
        if let cue = orderedCues.first(where: { type == "sign" ? $0.anchors.contains(where: { $0.frame == target }) : $0.start == target }) {
            selection = cue.id; currentTrack = cue.track
            selectedSign = type == "sign" ? cue.anchors.first { $0.frame == target }?.id : nil
        }
    }
    private func findNext() {
        let matches = orderedCues.filter { cue in
            guard searchRole == nil || cue.roleID == searchRole else { return false }
            if query.isEmpty { return searchRole != nil }
            if wholeWords {
                let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: query) + "(?![\\p{L}\\p{N}_])"
                let regex = try? NSRegularExpression(pattern: pattern, options: exactCase ? [] : [.caseInsensitive])
                return regex?.firstMatch(in: cue.text, range: NSRange(cue.text.startIndex..., in: cue.text)) != nil
            }
            return cue.text.range(of: query, options: exactCase ? [] : [.caseInsensitive]) != nil
        }
        guard let cue = matches.first(where: { $0.start > frame }) ?? matches.first else { error = "Aucune phrase trouvée."; return }
        select(cue, edit: false)
    }
    private func applyInput() {
        do {
            if panel == .shift {
                guard let value = Int(input) else { throw ProjectError.invalid("Saisir un décalage entier en images.") }
                try project.shift(by: value)
            } else {
                guard let value = Timecode.parse(input, fps: project.framesPerSecond) else { throw ProjectError.invalid("Timecode invalide : HH:MM:SS:II.") }
                if panel == .timestamp { try project.shift(by: value - project.mediaStartFrame, includingMediaOrigin: true) }
                else { seek(to: value) }
            }
            panel = nil
        } catch { self.error = error.localizedDescription }
    }
    private func chooseMedia(audio: Bool) {
        let picker = NSOpenPanel(); picker.allowedContentTypes = audio ? [.audio] : [.movie]; picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        if audio { transport.openVI(url); project.audioPath = url.path }
        else { transport.open(url); project.videoPath = url.path }
    }
    private func importDetX() {
        if !project.cues.isEmpty {
            let alert = NSAlert(); alert.messageText = "Remplacer la détection courante ?"
            alert.informativeText = "Enregistrez votre travail avant de remplacer son contenu."
            alert.addButton(withTitle: "Annuler"); alert.addButton(withTitle: "Remplacer")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.detx, .xml]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let imported = try DetX.read(Data(contentsOf: url), fps: project.framesPerSecond)
            transport.setRate(0); selection = nil; selectedSign = nil; editingPhrase = false; project = imported
            seek(to: imported.lastPositionFrame ?? imported.mediaStartFrame)
        } catch { self.error = error.localizedDescription }
    }
    private func exportData(type: UTType, name: String, data: () throws -> Data) {
        do {
            let contents = try data()
            let picker = NSSavePanel(); picker.allowedContentTypes = [type]; picker.nameFieldStringValue = name
            guard picker.runModal() == .OK, let url = picker.url else { return }
            try contents.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    private func verify() {
        do {
            try project.validate()
            var messages: [String] = []
            for cue in orderedCues {
                if cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { messages.append("\(Timecode.format(cue.start, fps: project.framesPerSecond)) : phrase vide.") }
                if cue.roleID == nil { messages.append("\(Timecode.format(cue.start, fps: project.framesPerSecond)) : rôle manquant.") }
            }
            for track in 0..<4 {
                let cues = orderedCues.filter { $0.track == track }
                for (left, right) in zip(cues, cues.dropFirst()) where left.end > right.start {
                    messages.append("Piste \(track + 1), \(Timecode.format(right.start, fps: project.framesPerSecond)) : chevauchement de phrases.")
                }
            }
            validationReport = messages.isEmpty ? "Aucune erreur détectée dans les contrôles disponibles : bornes, signes, rôles et chevauchements de phrases." : messages.joined(separator: "\n\n")
        } catch { validationReport = error.localizedDescription }
        panel = .validation
    }
    private func prompt(_ title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24); alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

@MainActor
private final class ProjectionController: ObservableObject {
    private var window: NSWindow?
    func show(project: Binding<Project>, transport: Transport, pixelsPerSecond: Double, fontName: String, fontSize: Double) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let view = ProjectionView(project: project, transport: transport, pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Cappella — Écran de contrôle"; window.styleMask.insert([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 1000, height: 650))
        if NSScreen.screens.count > 1, let screen = NSScreen.screens.last { window.setFrame(screen.visibleFrame, display: false) }
        else { window.center() }
        self.window = window; window.makeKeyAndOrderFront(nil)
    }
    func close() { window?.close(); window = nil }
}
private struct ProjectionView: View {
    @Binding var project: Project
    @ObservedObject var transport: Transport
    var pixelsPerSecond: Double
    var fontName: String
    var fontSize: Double
    @State private var video = AVPlayer()
    var body: some View {
        VStack(spacing: 0) {
            NativeVideoView(player: video)
            RythmoView(project: project, frame: project.mediaStartFrame + Int(transport.seconds * Double(project.framesPerSecond)),
                       pixelsPerSecond: pixelsPerSecond, fontName: fontName, fontSize: fontSize,
                       showGrid: true, showDetection: true, selectedSign: nil).frame(height: 160)
        }.frame(minWidth: 700, minHeight: 450)
        .onAppear(perform: attachVideo)
        .onChange(of: transport.mediaID) { _ in attachVideo() }
        .onChange(of: transport.rate) { rate in
            if rate > 0 { video.playImmediately(atRate: rate) } else { video.pause() }
        }
        .onChange(of: transport.seconds) { seconds in
            let time = video.currentTime().seconds
            if transport.rate <= 0 || !time.isFinite || abs(time - seconds) > 0.08 {
                video.seek(to: CMTime(seconds: seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        .onDisappear { video.pause() }
    }
    private func attachVideo() {
        video.pause(); video.isMuted = true
        video.replaceCurrentItem(with: transport.player.currentItem.map { AVPlayerItem(asset: $0.asset) })
        video.seek(to: CMTime(seconds: transport.seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
        if transport.rate > 0 { video.playImmediately(atRate: transport.rate) }
    }
}
