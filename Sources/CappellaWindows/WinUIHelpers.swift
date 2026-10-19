import Foundation
import UWP
import WinUI
import WinAppSDK
import WindowsFoundation

func uiSize(width: Double, height: Double) -> WindowsFoundation.Size {
    WindowsFoundation.Size(width: Float(width), height: Float(height))
}

func brush(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) -> SolidColorBrush {
    SolidColorBrush(Color(a: UInt8(alpha * 255), r: UInt8(red * 255), g: UInt8(green * 255), b: UInt8(blue * 255)))
}
func ink(_ value: UInt32) -> SolidColorBrush {
    brush(Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
}
func label(_ text: String, size: Double = 13, color: SolidColorBrush? = nil) -> TextBlock {
    let view = TextBlock(); view.text = text; view.fontSize = size
    if let color { view.foreground = color }
    return view
}
func button(_ text: String, action: @escaping () -> Void) -> Button {
    let view = Button(); view.content = text
    view.click.addHandler { _, _ in action() }
    return view
}
func place(_ view: FrameworkElement, on canvas: Canvas, x: Double, y: Double, width: Double? = nil, height: Double? = nil) {
    try? Canvas.setLeft(view, x); try? Canvas.setTop(view, y)
    if let width { view.width = width }; if let height { view.height = height }
    canvas.children.append(view)
}
func rectangle(on canvas: Canvas, x: Double, y: Double, width: Double, height: Double, color: SolidColorBrush) {
    guard width > 0, height > 0 else { return }
    let shape = Rectangle(); shape.fill = color
    place(shape, on: canvas, x: x, y: y, width: width, height: height)
}
func stack(_ children: [UIElement], spacing: Double = 10) -> StackPanel {
    let view = StackPanel(); view.spacing = spacing
    for child in children { view.children.append(child) }
    return view
}
func textField(_ text: String = "", placeholder: String = "") -> TextBox {
    let view = TextBox(); view.text = text; view.placeholderText = placeholder; return view
}
func row(_ children: [UIElement], spacing: Double = 10) -> StackPanel {
    let view = stack(children, spacing: spacing); view.orientation = .horizontal; return view
}
