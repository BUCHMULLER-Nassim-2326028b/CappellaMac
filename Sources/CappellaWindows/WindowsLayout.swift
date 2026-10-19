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
    func fitBandHeight() {
        guard root.actualHeight > 0, let row = root.rowDefinitions.getAt(3) else { return }
        let height = min(max(120, root.actualHeight - 190), max(120, self.document.preferences.bandHeight))
        if height != appliedBandHeight {
            row.height = GridLength(value: height, gridUnitType: .pixel)
            appliedBandHeight = height
        }
    }
    func makeResizeHandle(vertical: Bool, position: @escaping () -> Double,
                          change: @escaping (Double) -> Void, finish: @escaping () -> Void) -> Border {
        let handle = Border()
        handle.background = brush(0.5, 0.5, 0.5, alpha: 0.35)
        handle.protectedCursor = try? InputSystemCursor.create(vertical ? .sizeWestEast : .sizeNorthSouth)
        let region = WindowsResizeRegion(element: handle, vertical: vertical, position: position, change: change, finish: finish)
        let regionIndex = resizeRegions.count
        resizeRegions.append(region)
        // Also support WinUI pointer input when Windows delivers pointer events
        // instead of legacy mouse messages. The drag timer follows the cursor.
        handle.pointerPressed.addHandler { [weak self] _, args in
            guard let self, let args, let point = try? args.getCurrentPoint(root),
                  point.properties.isLeftButtonPressed else { return }
            guard resizeRegions.indices.contains(regionIndex) else { return }
            beginResize(resizeRegions[regionIndex]); args.handled = true
        }
        return handle
    }
}