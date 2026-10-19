import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func installWindowChrome() {
        let captionRow = RowDefinition(); captionRow.height = GridLength(value: 32, gridUnitType: .pixel)
        let contentRow = RowDefinition(); contentRow.height = GridLength(value: 1, gridUnitType: .star)
        windowChrome.rowDefinitions.append(captionRow); windowChrome.rowDefinitions.append(contentRow)
        customTitleBar.height = 32
        let iconColumn = ColumnDefinition(); iconColumn.width = GridLength(value: 40, gridUnitType: .pixel)
        let textColumn = ColumnDefinition(); textColumn.width = GridLength(value: 1, gridUnitType: .star)
        customTitleBar.columnDefinitions.append(iconColumn); customTitleBar.columnDefinitions.append(textColumn)
        titleLogo.width = 24; titleLogo.height = 24; titleLogo.stretch = .uniform
        titleText.verticalAlignment = .center; titleText.textTrimming = .characterEllipsis
        try? Grid.setColumn(titleText, 1)
        customTitleBar.children.append(titleLogo); customTitleBar.children.append(titleText)
        windowChrome.children.append(customTitleBar)
        try? Grid.setRow(root, 1); windowChrome.children.append(root)
        window.content = windowChrome
        window.extendsContentIntoTitleBar = true
        try? window.setTitleBar(customTitleBar)
        windowChrome.sizeChanged.addHandler { [weak self] _, _ in self?.updateCaptionInsets() }
        windowChrome.loaded.addHandler { [weak self] _, _ in self?.updateCaptionInsets() }
        updateCaptionInsets()
        // A noninteractive, programmatically focusable target for transport keys.
        timelineFocus.width = 1; timelineFocus.height = 1; timelineFocus.opacity = 0
        timelineFocus.isHitTestVisible = false; timelineFocus.isTabStop = false
        timelineFocus.horizontalAlignment = .left; timelineFocus.verticalAlignment = .top
        root.children.append(timelineFocus)
        root.pointerReleased.addHandler { [weak self] _, _ in self?.restoreTimelineFocus() }
        root.previewKeyUp.addHandler { [weak self] _, args in
            guard let self, let args, args.key.rawValue == 32, !dialogShowing,
                  !self.document.editing, !hasOpenPopup else { return }
            // Menu/button activation also consumes Space on key-up.
            args.handled = true
        }
    }
    func updateCaptionInsets() {
        let dpi = max(1, root.xamlRoot?.rasterizationScale ?? 1)
        let caption = window.appWindow.titleBar!
        customTitleBar.padding = Thickness(left: Double(caption.leftInset) / dpi, top: 0,
            right: max(138, Double(caption.rightInset) / dpi), bottom: 0)
    }
    func refreshWindowChrome() {
        func color(_ value: UInt32) -> UWP.Color {
            UWP.Color(a: 255, r: UInt8((value >> 16) & 255), g: UInt8((value >> 8) & 255), b: UInt8(value & 255))
        }
        windowChrome.requestedTheme = dark ? .dark : .light
        windowChrome.background = ink(dark ? 0x202020 : 0xF6F7F8)
        customTitleBar.background = ink(dark ? 0x202020 : 0xF6F7F8)
        titleText.foreground = ink(dark ? 0xF0F0F0 : 0x202020)
        let caption = window.appWindow.titleBar!
        let background = color(dark ? 0x202020 : 0xF6F7F8)
        let foreground = color(dark ? 0xF0F0F0 : 0x202020)
        caption.backgroundColor = background; caption.inactiveBackgroundColor = background
        caption.foregroundColor = foreground; caption.inactiveForegroundColor = color(dark ? 0x999999 : 0x777777)
        caption.buttonBackgroundColor = background; caption.buttonInactiveBackgroundColor = background
        caption.buttonForegroundColor = foreground; caption.buttonInactiveForegroundColor = caption.inactiveForegroundColor
        caption.buttonHoverBackgroundColor = color(dark ? 0x383838 : 0xE5E5E5)
        caption.buttonHoverForegroundColor = foreground
        caption.buttonPressedBackgroundColor = color(dark ? 0x484848 : 0xD8D8D8)
        caption.buttonPressedForegroundColor = foreground
        let logo = resources.appendingPathComponent(dark ? "CappellaLogo_dark.png" : "CappellaLogo.png")
        if FileManager.default.fileExists(atPath: logo.path) { titleLogo.source = BitmapImage(Uri(logo.absoluteString)) }
    }
    var hasOpenPopup: Bool {
        guard let xamlRoot = root.xamlRoot,
              let popups = try? VisualTreeHelper.getOpenPopupsForXamlRoot(xamlRoot) else { return false }
        return popups.size > 0
    }
    func restoreTimelineFocus() {
        _ = try? window.dispatcherQueue.tryEnqueue { [weak self] in
            guard let self, !dialogShowing, !self.document.editing, !isResizing, !hasOpenPopup else { return }
            _ = try? timelineFocus.focus(.programmatic)
        }
    }
    func makeResizeHandle(vertical: Bool, position: @escaping () -> Double,
                          change: @escaping (Double) -> Void, finish: @escaping () -> Void) -> Border {
        let handle = Border()
        handle.background = brush(0.5, 0.5, 0.5, alpha: 0.35)
        handle.protectedCursor = try? InputSystemCursor.create(vertical ? .sizeWestEast : .sizeNorthSouth)
        var drag: (coordinate: Double, initial: Double)?
        func complete() {
            guard drag != nil else { return }
            drag = nil; isResizing = false; finish(); restoreTimelineFocus()
        }
        handle.pointerPressed.addHandler { [weak self, weak handle] _, args in
            guard let self, let handle, let args,
                  let point = try? args.getCurrentPoint(root), point.properties.isLeftButtonPressed else { return }
            guard (try? handle.capturePointer(args.pointer)) == true else { return }
            drag = (vertical ? Double(point.position.x) : Double(point.position.y), position())
            isResizing = true; args.handled = true
        }
        handle.pointerMoved.addHandler { [weak self] _, args in
            guard let self, let drag, let args, let point = try? args.getCurrentPoint(root) else { return }
            let current = vertical ? Double(point.position.x) : Double(point.position.y)
            change(drag.initial + current - drag.coordinate); args.handled = true
        }
        handle.pointerReleased.addHandler { [weak handle] _, args in
            guard drag != nil else { return }
            complete(); try? handle?.releasePointerCaptures(); args?.handled = true
        }
        handle.pointerCanceled.addHandler { [weak handle] _, _ in complete(); try? handle?.releasePointerCaptures() }
        handle.pointerCaptureLost.addHandler { _, _ in complete() }
        return handle
    }
}