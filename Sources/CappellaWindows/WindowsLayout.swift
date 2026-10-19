import Foundation
import CappellaCore
import WinUI
import WinAppSDK
import UWP
import WindowsFoundation

extension WindowsEditor {
    func makeClockPanel() -> Border {
        clockPanel.padding = Thickness(left: 7, top: 5, right: 7, bottom: 5)
        clockPanel.borderBrush = ink(0x70777C)
        clockPanel.borderThickness = Thickness(left: 0, top: 0.5, right: 0, bottom: 0)
        let content = Grid()
        let headerRow = RowDefinition(); headerRow.height = GridLength(value: 0, gridUnitType: .auto)
        let detailsRow = RowDefinition(); detailsRow.height = GridLength(value: 1, gridUnitType: .star)
        let footerRow = RowDefinition(); footerRow.height = GridLength(value: 18, gridUnitType: .pixel)
        content.rowDefinitions.append(headerRow); content.rowDefinitions.append(detailsRow); content.rowDefinitions.append(footerRow)
        let caption = label("timecode", size: 10, color: ink(0xFFFFFF))
        caption.width = 52; caption.verticalAlignment = .bottom
        caption.margin = Thickness(left: 0, top: 0, right: 0, bottom: 7)
        timecode.fontFamily = FontFamily("Segoe UI")
        timecode.fontWeight = FontWeights.light
        let header = row([caption, timecode], spacing: 9)
        header.tapped.addHandler { [weak self] _, _ in
            Task { @MainActor [weak self] in await self?.goTimecode() }
        }
        content.children.append(header)
        loopLabel.verticalAlignment = .top
        loopLabel.margin = Thickness(left: 0, top: 3, right: 0, bottom: 0)
        try? Grid.setRow(loopLabel, 1); content.children.append(loopLabel)
        let footer = Grid()
        for unit in [GridUnitType.star, .auto, .star] {
            let column = ColumnDefinition(); column.width = GridLength(value: 1, gridUnitType: unit)
            footer.columnDefinitions.append(column)
        }
        loopRange.verticalAlignment = .center; loopRange.textTrimming = .characterEllipsis
        footer.children.append(loopRange)
        for control in [vo, vi] {
            control.fontSize = 10
            control.minWidth = 0; control.minHeight = 0; control.width = 17; control.height = 18
            control.padding = Thickness(); control.borderThickness = Thickness()
            control.background = brush(0, 0, 0, alpha: 0)
            control.borderBrush = brush(0, 0, 0, alpha: 0)
            control.isTabStop = false
            for key in ["ButtonBackgroundPointerOver", "ButtonBackgroundPressed", "ButtonBorderBrushPointerOver", "ButtonBorderBrushPressed"] {
                _ = control.resources.insert(key, brush(0, 0, 0, alpha: 0))
            }
        }
        let switches = row([vo, vi], spacing: 3)
        try? Grid.setColumn(switches, 1); footer.children.append(switches)
        try? Grid.setRow(footer, 2); content.children.append(footer)
        clockPanel.child = content
        refreshClockStyle()
        return clockPanel
    }
    func refreshClockStyle() {
        clockPanel.background = ink(dark ? 0x171717 : 0x232B31)
        timecode.foreground = ink(0xFFFFFF); loopLabel.foreground = ink(0xDDDDDD)
        loopRange.foreground = ink(dark ? 0xB8C1C7 : 0x6E8796)
        let muted = dark ? UInt32(0x919DA5) : UInt32(0x647785)
        vo.foreground = ink(media.hasMedia && !media.usingVI ? 0xFFFFFF : muted)
        vi.foreground = ink(media.hasMedia && media.usingVI ? 0xFFFFFF : muted)
        vo.opacity = 1; vi.opacity = 1
    }
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