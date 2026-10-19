import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func refreshScript() {
        if scriptRevision != self.document.revision {
            let cues = self.document.project.cues.sorted { $0.start < $1.start }
            let order = cues.map(\.id)
            if order != scriptOrder {
                script.children.clear(); scriptRows.removeAll(); scriptModels.removeAll(); scriptSelection = nil
                for cue in cues {
                    let header = label("", size: 11); header.fontFamily = FontFamily("Courier New")
                    let text = label("", size: 12); text.fontFamily = FontFamily("Courier New"); text.textWrapping = .wrap
                    let container = Border(); container.child = stack([header, text], spacing: 2)
                    let id = cue.id
                    container.tapped.addHandler { [weak self] _, _ in
                        guard let self, let current = self.document.project.cues.first(where: { $0.id == id }) else { return }
                        media.stop(); self.document.selection = current.id; self.document.track = current.track
                        seek(current.start); refreshScript()
                    }
                    script.children.append(container); scriptRows[cue.id] = (container, header, text)
                }
                scriptOrder = order
            }
            let rolesChanged = scriptRoles != self.document.project.roles || scriptFPS != fps
            let names = Dictionary(uniqueKeysWithValues: self.document.project.roles.map { ($0.id, $0.name) })
            for cue in cues {
                guard let row = scriptRows[cue.id], rolesChanged || scriptModels[cue.id] != cue else { continue }
                let name = cue.roleID.flatMap { names[$0] } ?? "Sans rôle"
                let header = Timecode.format(cue.start, fps: fps) + " — " + name + " :"
                if row.header.text != header { row.header.text = header }
                if row.text.text != cue.text { row.text.text = cue.text }
            }
            scriptModels = Dictionary(uniqueKeysWithValues: cues.map { ($0.id, $0) })
            scriptRoles = self.document.project.roles; scriptFPS = fps
            scriptRevision = self.document.revision
        }
        if scriptSelection != self.document.selection {
            if let previous = scriptSelection { scriptRows[previous]?.border.background = nil }
            if let current = self.document.selection { scriptRows[current]?.border.background = brush(0.2, 0.5, 1, alpha: 0.12) }
            scriptSelection = self.document.selection
        }
    }
}
