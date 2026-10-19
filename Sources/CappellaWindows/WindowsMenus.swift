import Foundation
import CappellaCore
import WinUI
import UWP
import WindowsFoundation
import WinSDK

extension WindowsEditor {
    func menuItem(_ title: String, shortcut: String = "", action: @escaping () -> Void) -> MenuFlyoutItem {
        let item = MenuFlyoutItem(); item.text = title
        if !shortcut.isEmpty { item.keyboardAcceleratorTextOverride = shortcut }
        item.click.addHandler { [weak self] _, _ in action(); self?.restoreTimelineFocus() }
        return item
    }
    func asyncItem(_ title: String, shortcut: String = "", action: @escaping @MainActor () async -> Void) -> MenuFlyoutItem {
        menuItem(title, shortcut: shortcut) { Task { @MainActor in await action() } }
    }
    func makeMenu() -> MenuBar {
        let bar = MenuBar()
        func menu(_ name: String, _ items: [MenuFlyoutItemBase]) {
            let menu = MenuBarItem(); menu.title = name
            for item in items { menu.items.append(item) }; bar.items.append(menu)
        }
        menu("Fichier", [
            asyncItem("Nouveau", shortcut: "Ctrl+N") { [unowned self] in if await mayReplace() { media.stop(); self.document.replace(with: Project(), url: nil) } },
            asyncItem("Ouvrir…", shortcut: "Ctrl+O") { [unowned self] in if let url = await pickFile([".detx", ".cappellaproject"]) { await open(url) } },
            asyncItem("Ouvrir une sauvegarde…") { [unowned self] in if let url = await pickFile([".cappellaproject"]) { await open(url, recovery: true) } },
            MenuFlyoutSeparator(),
            asyncItem("Enregistrer", shortcut: "Ctrl+S") { [unowned self] in _ = await save() },
            asyncItem("Enregistrer sous…", shortcut: "Ctrl+Maj+S") { [unowned self] in _ = await save(as: true) },
            asyncItem("Enregistrer une copie sous…", shortcut: "Ctrl+Alt+S") { [unowned self] in _ = await save(copy: true) },
            MenuFlyoutSeparator(),
            asyncItem("Ouvrir l'image…", shortcut: "Ctrl+Maj+V") { [unowned self] in await chooseMedia(audio: false) },
            asyncItem("Propriétés…", shortcut: "Ctrl+P") { [unowned self] in await properties() },
            asyncItem("Exporter le script…") { [unowned self] in await exportText(crossTable: false) },
            asyncItem("Exporter le croisillé…") { [unowned self] in await exportText(crossTable: true) },
            MenuFlyoutSeparator(),
            asyncItem("Quitter") { [unowned self] in if await mayReplace() { self.document.replace(with: Project(), url: nil); try? window.close() } }
        ])
        let tracks = MenuFlyoutSubItem(); tracks.text = "Piste"
        tracks.items.append(menuItem("Piste précédente", shortcut: "Ctrl+Haut") { [unowned self] in self.document.selectTrack(self.document.track - 1) })
        tracks.items.append(menuItem("Piste suivante", shortcut: "Ctrl+Bas") { [unowned self] in self.document.selectTrack(self.document.track + 1) })
        tracks.items.append(MenuFlyoutSeparator())
        for track in 0..<4 { tracks.items.append(menuItem("Piste \(track + 1)", shortcut: "F\(track + 5)") { [unowned self] in self.document.selectTrack(track) }) }
        let signs = MenuFlyoutSubItem(); signs.text = "Ajouter un signe"
        for (name, kind) in signKinds {
            signs.items.append(menuItem(name) { [unowned self] in addSign(kind) })
        }
        signs.items.append(MenuFlyoutSeparator())
        signs.items.append(menuItem("Boucle") { [unowned self] in addMarker(loop: true) })
        signs.items.append(menuItem("Changement de plan") { [unowned self] in addMarker(loop: false) })
        menu("Édition", [
            menuItem("Annuler", shortcut: "Ctrl+Z") { [unowned self] in self.document.undo() },
            menuItem("Rétablir", shortcut: "Ctrl+Y") { [unowned self] in self.document.redo() },
            MenuFlyoutSeparator(),
            menuItem("Couper", shortcut: "Ctrl+X") { [unowned self] in copyPhrase(cut: true) },
            menuItem("Copier", shortcut: "Ctrl+C") { [unowned self] in copyPhrase() },
            asyncItem("Coller", shortcut: "Ctrl+V") { [unowned self] in await pastePhrase() },
            asyncItem("Rechercher…", shortcut: "Ctrl+F") { [unowned self] in await find() },
            MenuFlyoutSeparator(), tracks, signs,
            menuItem("Supprimer le signe", shortcut: "Suppr") { [unowned self] in perform { try self.document.removeSign() } },
            menuItem("Décrocher tous les signes", shortcut: "Ctrl+Maj+D") { [unowned self] in detachSigns() },
            MenuFlyoutSeparator(),
            asyncItem("Mode Édition / Mode Détection", shortcut: "Entrée") { [unowned self] in await toggleEditing() },
            menuItem("Annuler la phrase", shortcut: "Échap") { [unowned self] in self.document.cancelEditing(); updateTextEditor() },
            menuItem("Supprimer la phrase", shortcut: "Ctrl+Suppr") { [unowned self] in perform { try self.document.deletePhrase() } },
            menuItem("Voix off", shortcut: "Ctrl+U") { [unowned self] in perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } } },
            asyncItem("Rôles…", shortcut: "Ctrl+R") { [unowned self] in await roles() },
            menuItem("Vérifier", shortcut: "F4") { [unowned self] in perform { try self.document.project.validate() }; Task { await showError("Vérification terminée.") } },
            asyncItem("Décaler la rythmo…") { [unowned self] in await shift() },
            MenuFlyoutSeparator(),
            asyncItem("Préférences…") { [unowned self] in await preferences() }
        ])
        var control: [MenuFlyoutItemBase] = [
            menuItem("Lecture / Pause", shortcut: "Espace") { [unowned self] in togglePlay() },
            menuItem("Lecture avant", shortcut: "Haut") { [unowned self] in setRate(1) },
            menuItem("Lecture inverse", shortcut: "Bas") { [unowned self] in setRate(-1) },
            menuItem("Stop") { [unowned self] in media.stop() },
            menuItem("Image suivante", shortcut: "Alt+Droite") { [unowned self] in media.stop(); seek(self.document.frame + 1) },
            menuItem("Image précédente", shortcut: "Alt+Gauche") { [unowned self] in media.stop(); seek(self.document.frame - 1) },
            MenuFlyoutSeparator()
        ]
        for (title, kind, direction) in [("Signe précédent", "sign", -1), ("Signe suivant", "sign", 1), ("Phrase précédente", "phrase", -1), ("Phrase suivante", "phrase", 1), ("Boucle précédente", "loop", -1), ("Boucle suivante", "loop", 1), ("Plan précédent", "shot", -1), ("Plan suivant", "shot", 1)] {
            control.append(menuItem(title) { [unowned self] in navigate(kind, direction) })
        }
        menu("Contrôle", control)
        menu("Position", [asyncItem("Aller au timecode…", shortcut: "Ctrl+G") { [unowned self] in await goTimecode() }, menuItem("Marquer cette position", shortcut: "Ctrl+D") { [unowned self] in markPosition() }])
        menu("Affichage", [
            menuItem("Détection") { [unowned self] in self.document.preferences.showDetection.toggle(); self.document.preferences.save(); refresh() },
            menuItem("Grille et signes") { [unowned self] in self.document.preferences.showGrid.toggle(); self.document.preferences.save(); refresh() },
            menuItem("Zoom avant", shortcut: "+") { [unowned self] in zoom(1.25) },
            menuItem("Zoom arrière", shortcut: "−") { [unowned self] in zoom(0.8) },
            menuItem("Écran de contrôle") { [unowned self] in showProjection() }
        ])
        menu("Audio", [
            menuItem("Basculer VO / VI", shortcut: "F2") { [unowned self] in media.toggleVI(); refreshClock() },
            asyncItem("Ouvrir le son…") { [unowned self] in await chooseMedia(audio: true) },
            menuItem("Monter le volume") { [unowned self] in media.volume = min(1, media.volume + 0.1); media.applyAudio() },
            menuItem("Baisser le volume") { [unowned self] in media.volume = max(0, media.volume - 0.1); media.applyAudio() },
            menuItem("Couper le son") { [unowned self] in media.muted.toggle(); media.applyAudio() }
        ])
        menu("Aide", [
            menuItem("Documentation", shortcut: "F1") { [unowned self] in openWeb("https://cappella.app/") },
            menuItem("Raccourcis clavier") { [unowned self] in openWeb("https://cappella.app/documentation11.html") },
            menuItem("Rechercher des mises à jour") { [unowned self] in openWeb("https://github.com/BUCHMULLER-Nassim-2326028b/CappellaMac/releases") },
            asyncItem("À propos de Cappella") { [unowned self] in await about() }
        ])
        return bar
    }
    var signKinds: [(String, String)] { [
        ("Début de phrase ouverte", "in_open"), ("Fin de phrase ouverte", "out_open"),
        ("Début de phrase fermée", "in_close"), ("Fin de phrase fermée", "out_close"),
        ("Labiale m, b, p", "mpb"), ("Demi-labiale f, v, r", "fvr"), ("Neutre", "neutral"),
        ("Cul de poule", "weuque"), ("Grande ouverture A", "a"), ("Ouverture en rond O", "o")
    ] }
    func togglePlay() { setRate(media.rate == 0 ? 1 : 0) }
    func setRate(_ rate: Double) {
        self.document.finishEditing(); logicalFrame = Double(self.document.frame); lastTick = Date(); updateTextEditor(); perform { try media.setRate(rate) }
    }
    func navigate(_ kind: String, _ direction: Int) {
        media.stop(); if let frame = self.document.navigate(kind, direction) { seek(frame) }; updateTextEditor()
    }
    func zoom(_ factor: Double) { self.document.preferences.pixelsPerSecond = min(800, max(15, self.document.preferences.pixelsPerSecond * factor)); self.document.preferences.save(); renderBand(); updateTextEditor() }
    func addMarker(loop: Bool) {
        perform {
            try self.document.commit { project in
                if loop { if !project.loops.contains(where: { $0.frame == self.document.frame }) { project.loops.append(Marker(frame: self.document.frame, label: String(project.loops.count + 1))) } }
                else if !project.shots.contains(where: { $0.frame == self.document.frame }) { project.shots.append(Marker(frame: self.document.frame, label: String(project.shots.count + 1))) }
            }
        }
    }
    func addSign(_ kind: String) {
        if kind.hasPrefix("in_") { Task { @MainActor in await newPhrase(edit: false, kind: kind) } }
        else { perform { try self.document.addSign(kind) }; updateTextEditor() }
    }
    func detachSigns() {
        perform { try self.document.mutateCue { cue in
            var signs = cue.anchors
            for index in signs.indices { signs[index].textOffset = Int((Double(signs[index].frame - cue.start) / Double(max(1, cue.end - cue.start)) * Double(cue.text.unicodeScalars.count)).rounded()) }
            cue.signs = signs
        } }
    }
    func contextMenu(_ args: RightTappedRoutedEventArgs?) {
        guard let args, let point = try? args.getPosition(bandContainer) else { return }
        let (cue, sign, _, _) = hit(point); guard let cue else { return }
        self.document.selection = cue.id; self.document.track = cue.track; self.document.signSelection = sign?.id
        let menu = MenuFlyout()
        menu.items.append(menuItem("Supprimer la phrase") { [unowned self] in perform { try self.document.deletePhrase() } })
        let tracks = MenuFlyoutSubItem(); tracks.text = "Changer de piste"
        for track in 0..<4 { tracks.items.append(menuItem("Piste \(track + 1)") { [unowned self] in perform { try self.document.moveTrack(track) } }) }
        menu.items.append(tracks)
        menu.items.append(asyncItem("Changer rôle…") { [unowned self] in if let id = await chooseRole() { perform { try self.document.mutateCue { $0.roleID = id } } } })
        menu.items.append(menuItem("Voix off") { [unowned self] in perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } } })
        menu.items.append(menuItem("Décrocher tous les signes") { [unowned self] in detachSigns() })
        menu.items.append(MenuFlyoutSeparator())
        menu.items.append(menuItem("Couper") { [unowned self] in copyPhrase(cut: true) })
        menu.items.append(menuItem("Copier") { [unowned self] in copyPhrase() })
        menu.items.append(asyncItem("Coller") { [unowned self] in await pastePhrase() })
        menu.items.append(MenuFlyoutSeparator())
        let remove = menuItem("Supprimer le signe") { [unowned self] in perform { try self.document.removeSign() } }
        remove.isEnabled = sign != nil && sign?.id != cue.anchors.first?.id && sign?.id != cue.anchors.last?.id
        menu.items.append(remove)
        let detach = menuItem("Décrocher le signe") { [unowned self] in if let id = self.document.signSelection { perform { try self.document.mutateCue { Timeline.detachSign(in: &$0, id: id) } } } }
        detach.isEnabled = remove.isEnabled; menu.items.append(detach)
        let types = MenuFlyoutSubItem(); types.text = "Changer le type"; types.isEnabled = sign != nil
        for (name, kind) in signKinds where sign?.kind.hasPrefix("in_") == true ? kind.hasPrefix("in_") : sign?.kind.hasPrefix("out_") == true ? kind.hasPrefix("out_") : !kind.hasPrefix("in_") && !kind.hasPrefix("out_") {
            types.items.append(menuItem(name) { [unowned self] in perform { try self.document.mutateCue { cue in
                var signs = cue.anchors
                if let index = signs.firstIndex(where: { $0.id == self.document.signSelection }) { signs[index].kind = kind; cue.signs = signs }
            } } })
        }
        menu.items.append(types); try? menu.showAt(bandContainer, point); args.handled = true
    }
    func openWeb(_ url: String) { Task { _ = try? await Launcher.launchUriAsync(Uri(url)).get() } }
    func keyDown(_ args: KeyRoutedEventArgs?) {
        guard let args, !dialogShowing, !hasOpenPopup else { return }
        let key = Int(args.key.rawValue)
        let ctrl = GetKeyState(Int32(VK_CONTROL)) < 0, alt = GetKeyState(Int32(VK_MENU)) < 0, shift = GetKeyState(Int32(VK_SHIFT)) < 0
        if self.document.editing && !ctrl && !alt && ![13, 27].contains(key) { return }
        if ctrl {
            switch key {
            case 78: Task { if await mayReplace() { media.stop(); self.document.replace(with: Project(), url: nil) } }
            case 79: Task { if let url = await pickFile([".detx", ".cappellaproject"]) { await open(url) } }
            case 83: Task { _ = await save(as: shift, copy: alt) }
            case 90: self.document.undo()
            case 89: self.document.redo()
            case 67 where !self.document.editing: copyPhrase()
            case 88 where !self.document.editing: copyPhrase(cut: true)
            case 86 where !self.document.editing: Task { await pastePhrase() }
            case 70: Task { await find() }
            case 71: Task { await goTimecode() }
            case 80: Task { await properties() }
            case 82: Task { await roles() }
            case 85: perform { try self.document.mutateCue { $0.voice = $0.voice == "off" ? nil : "off" } }
            case 38: self.document.selectTrack(self.document.track - 1)
            case 40: self.document.selectTrack(self.document.track + 1)
            case 46: perform { try self.document.deletePhrase() }
            case 68: if shift { detachSigns() } else { markPosition() }
            case 120: navigate("role", -1)
            case 121: navigate("role", 1)
            case 116...119: perform { try self.document.moveTrack(key - 116) }
            default: return
            }
        } else {
            switch key {
            case 32:
                args.handled = true; restoreTimelineFocus(); togglePlay(); return
            case 38: setRate(1)
            case 40: setRate(-1)
            case 37: if alt { media.stop(); seek(self.document.frame - 1) } else { navigate("sign", -1) }
            case 39: if alt { media.stop(); seek(self.document.frame + 1) } else { navigate("sign", 1) }
            case 13: Task { await toggleEditing() }
            case 27: self.document.cancelEditing(); updateTextEditor()
            case 113: media.toggleVI(); refreshClock()
            case 115: perform { try self.document.project.validate() }
            case 116...119: self.document.selectTrack(key - 116)
            case 120: navigate("phrase", -1)
            case 121: navigate("phrase", 1)
            case 122: navigate("loop", -1)
            case 123: navigate("loop", 1)
            case 9: navigate("phrase", shift ? 1 : -1)
            case 46: perform { try self.document.removeSign() }
            case 107, 187: zoom(1.25)
            case 109, 189: zoom(0.8)
            case 96: addMarker(loop: true)
            case 97: addMarker(loop: false)
            case 98: addSign("in_open")
            case 99: addSign("out_open")
            case 100: addSign("mpb")
            case 101: addSign("fvr")
            case 102: addSign("neutral")
            case 103: addSign("a")
            case 104: addSign("o")
            case 105: addSign("weuque")
            default: return
            }
        }
        args.handled = true
    }
}
