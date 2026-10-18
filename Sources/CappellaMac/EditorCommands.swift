import SwiftUI
import AppKit

enum EditorAction {
    case openMedia, openVI, importDetX, importRoles, exportDetX, exportScript, exportCrossTable
    case roles, properties, find, goTimecode, shift, timestamp, check, preferences
    case playPause, stop, step(Int), rate(Float), navigate(String, Int)
    case addPhrase, deletePhrase, track(Int), mode, addSign(String), deleteSign, shiftSign(Int), voiceOff
    case addLoop, addShot, markPosition, positions, zoom(Double), grid, detection, fullScreen, projection
    case toggleVI, mute, volume(Float)
}

struct EditorActions {
    var perform: (EditorAction) -> Void
    var hasSelection: Bool
    var hasSign: Bool
    var showGrid: Bool
    var showDetection: Bool
    var detectionMode: Bool
}

private struct EditorActionsKey: FocusedValueKey { typealias Value = EditorActions }
extension FocusedValues {
    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

struct CappellaCommands: Commands {
    @FocusedValue(\.editorActions) private var editor
    private func run(_ action: EditorAction) { editor?.perform(action) }
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Divider()
            Button("Ouvrir l'image…") { run(.openMedia) }.keyboardShortcut("v", modifiers: [.command, .shift])
            Menu("Importer") {
                Button("Détection DetX…") { run(.importDetX) }
                Button("Liste de rôles d'un DetX…") { run(.importRoles) }
            }
            Menu("Exporter") {
                Button("Document DetX…") { run(.exportDetX) }
                Button("Script…") { run(.exportScript) }.keyboardShortcut("e")
                Button("Croisillé CSV…") { run(.exportCrossTable) }
            }
            Button("Propriétés…") { run(.properties) }.keyboardShortcut("p")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Rechercher…") { run(.find) }.keyboardShortcut("f")
            Menu("Piste") {
                ForEach(0..<4) { track in Button("Piste \(track + 1)") { run(.track(track)) } }
            }
            Menu("Ajouter un signe") {
                Button("Début de phrase ouverte") { run(.addSign("in_open")) }
                Button("Fin de phrase ouverte") { run(.addSign("out_open")) }
                Button("Début de phrase fermée") { run(.addSign("in_close")) }
                Button("Fin de phrase fermée") { run(.addSign("out_close")) }
                Divider()
                Button("Labiale m,b,p") { run(.addSign("mpb")) }
                Button("Demi-labiale f,v,r") { run(.addSign("fvr")) }
                Button("Neutre") { run(.addSign("neutral")) }
                Button("Cul de poule w, eu, que") { run(.addSign("weuque")) }
                Divider()
                Button("Boucle") { run(.addLoop) }
                Button("Changement de plan") { run(.addShot) }
            }
            Button("Déplacer le signe à gauche") { run(.shiftSign(-1)) }.disabled(editor?.hasSign != true)
            Button("Déplacer le signe à droite") { run(.shiftSign(1)) }.disabled(editor?.hasSign != true)
            Button("Supprimer le signe") { run(.deleteSign) }.disabled(editor?.hasSign != true)
            Divider()
            Button(editor?.detectionMode == true ? "Passer en mode Édition" : "Passer en mode Détection") { run(.mode) }
            Button("Nouvelle phrase") { run(.addPhrase) }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Supprimer la phrase") { run(.deletePhrase) }.keyboardShortcut(.delete, modifiers: [.command])
                .disabled(editor?.hasSelection != true)
            Button("Voix off") { run(.voiceOff) }.keyboardShortcut("u").disabled(editor?.hasSelection != true)
            Button("Rôles…") { run(.roles) }.keyboardShortcut("r")
            Button("Vérifier") { run(.check) }
            Button("Décaler la rythmo…") { run(.shift) }
        }
        CommandMenu("Contrôle") {
            Button("Lecture / Pause") { run(.playPause) }
            Button("Lecture avant") { run(.rate(1)) }
            Button("Lecture inverse") { run(.rate(-1)) }
            Button("Stop") { run(.stop) }
            Divider()
            Button("Image suivante") { run(.step(1)) }
            Button("Image précédente") { run(.step(-1)) }
            Menu("Shuttle") {
                ForEach([-10.0, -3, -1, -0.75, -0.5, -0.25, -0.125, 0.125, 0.25, 0.5, 0.75, 1, 3, 10], id: \.self) { rate in
                    Button("\(rate < 0 ? "Arrière" : "Avant") ×\(abs(rate).formatted())") { run(.rate(Float(rate))) }
                }
            }
            Divider()
            Button("Signe précédent") { run(.navigate("sign", -1)) }
            Button("Signe suivant") { run(.navigate("sign", 1)) }
            Button("Phrase précédente") { run(.navigate("phrase", -1)) }
            Button("Phrase suivante") { run(.navigate("phrase", 1)) }
            Button("Phrase précédente de ce rôle") { run(.navigate("role", -1)) }
            Button("Phrase suivante de ce rôle") { run(.navigate("role", 1)) }
            Button("Boucle précédente") { run(.navigate("loop", -1)) }
            Button("Boucle suivante") { run(.navigate("loop", 1)) }
            Button("Plan précédent") { run(.navigate("shot", -1)) }
            Button("Plan suivant") { run(.navigate("shot", 1)) }
            Divider()
            Button("Changer le timestamp…") { run(.timestamp) }
        }
        CommandMenu("Position") {
            Button("Aller au timecode…") { run(.goTimecode) }.keyboardShortcut("g")
            Button("Marquer cette position…") { run(.markPosition) }.keyboardShortcut("d")
            Button("Positions mémorisées…") { run(.positions) }
        }
        CommandMenu("Affichage") {
            Toggle("Détection", isOn: Binding(get: { editor?.showDetection ?? true }, set: { _ in run(.detection) }))
            Toggle("Grille et signes", isOn: Binding(get: { editor?.showGrid ?? true }, set: { _ in run(.grid) }))
            Button("Plein écran") { run(.fullScreen) }.keyboardShortcut(.return, modifiers: [.option])
            Divider()
            Button("Zoom avant") { run(.zoom(1.25)) }.keyboardShortcut("+")
            Button("Zoom arrière") { run(.zoom(0.8)) }.keyboardShortcut("-")
            Button("Écran de contrôle") { run(.projection) }
        }
        CommandMenu("Audio") {
            Button("Ouvrir la piste VI…") { run(.openVI) }
            Button("Passer en VI / VO") { run(.toggleVI) }
            Divider()
            Button("Monter le volume") { run(.volume(0.1)) }
            Button("Baisser le volume") { run(.volume(-0.1)) }
            Button("Couper / rétablir le son") { run(.mute) }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Préférences…") { run(.preferences) }.keyboardShortcut(",")
        }
    }
}

/// Local key handling leaves normal typing, spaces and arrows to text editors.
struct EditorKeyboardMonitor: NSViewRepresentable {
    var perform: (EditorAction) -> Void
    func makeNSView(context: Context) -> KeyboardView { let view = KeyboardView(); view.perform = perform; return view }
    func updateNSView(_ view: KeyboardView, context: Context) { view.perform = perform }
    final class KeyboardView: NSView {
        var perform: ((EditorAction) -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window?.isKeyWindow == true,
                      !(self.window?.firstResponder is NSTextView),
                      !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) else { return event }
                let action: EditorAction?
                switch event.keyCode {
                case 49: action = .playPause
                case 123: action = event.modifierFlags.contains(.option) ? .step(-1) : .navigate("sign", -1)
                case 124: action = event.modifierFlags.contains(.option) ? .step(1) : .navigate("sign", 1)
                case 126: action = .rate(1)
                case 125: action = .rate(-1)
                case 36: action = .mode
                case 96: action = .track(0)
                case 97: action = .track(1)
                case 98: action = .track(2)
                case 100: action = .track(3)
                case 101: action = .navigate("phrase", -1)
                case 109: action = .navigate("phrase", 1)
                case 103: action = .navigate("loop", -1)
                case 111: action = .navigate("loop", 1)
                default:
                    switch event.charactersIgnoringModifiers {
                    case "2": action = .addSign("in_open")
                    case "3": action = .addSign("out_open")
                    case "4": action = .addSign("mpb")
                    case "5": action = .addSign("fvr")
                    case "6": action = .addSign("neutral")
                    case "9": action = .addSign("weuque")
                    case "0": action = .addLoop
                    case "1": action = .addShot
                    default: action = nil
                    }
                }
                guard let action else { return event }
                self.perform?(action); return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
