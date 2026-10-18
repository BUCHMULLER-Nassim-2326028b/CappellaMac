import SwiftUI
import CappellaCore

struct RythmoView: View {
    var project: Project
    var frame: Int
    var pixelsPerSecond: Double
    var fontName: String
    var fontSize: Double
    var showGrid: Bool
    var showDetection: Bool
    var selectedSign: UUID?
    var seek: (Int, Int) -> Void = { _, _ in }
    var moveSign: (UUID, UUID, Int) -> Void = { _, _, _ in }
    @State private var dragging = false
    @State private var dragReferenceFrame = 0
    @State private var dragSignFrame = 0
    @State private var draggedSign: (UUID, UUID)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let laneHeight = height / 4
            let scale = pixelsPerSecond / Double(project.framesPerSecond)
            let cursor = width / 2
            Canvas { context, size in
                for track in 0..<4 {
                    let rect = CGRect(x: 0, y: CGFloat(track) * laneHeight, width: size.width, height: laneHeight)
                    let colors: [Color] = track == 0 ? [Color(white: 0.99), Color(white: 0.90)] : [Color(white: 0.68), Color(white: 0.59)]
                    context.fill(Path(rect), with: .linearGradient(Gradient(colors: colors), startPoint: rect.origin, endPoint: CGPoint(x: 0, y: rect.maxY)))
                }
                if showGrid {
                    let start = frame - Int(cursor / scale) - 1
                    let end = frame + Int(cursor / scale) + 1
                    let step = max(1, Int(3 / scale))
                    var ticks = Path()
                    for f in stride(from: start - start % step, through: end, by: step) {
                        let x = cursor + Double(f - frame) * scale
                        let length: Double = f % project.framesPerSecond == 0 ? 7 : 2
                        for row in 0..<4 {
                            let y = Double(row) * laneHeight
                            ticks.move(to: CGPoint(x: x, y: y)); ticks.addLine(to: CGPoint(x: x, y: y + length))
                        }
                    }
                    context.stroke(ticks, with: .color(.black.opacity(0.5)), lineWidth: 0.5)
                    var lines = Path()
                    for row in 0...4 {
                        lines.move(to: CGPoint(x: 0, y: Double(row) * laneHeight))
                        lines.addLine(to: CGPoint(x: size.width, y: Double(row) * laneHeight))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.55)), lineWidth: 0.5)
                }
                if showDetection {
                    for shot in project.shots {
                        let x = cursor + Double(shot.frame - frame) * scale
                        guard x >= 0, x <= size.width else { continue }
                        var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    for loop in project.loops {
                        let x = cursor + Double(loop.frame - frame) * scale
                        guard x >= 0, x <= size.width else { continue }
                        context.fill(Path(CGRect(x: x, y: 0, width: 2, height: size.height)), with: .color(.orange.opacity(0.75)))
                        context.draw(Text(loop.label).font(.system(size: 10, weight: .bold)).foregroundColor(.black), at: CGPoint(x: x + 4, y: size.height - 8), anchor: .leading)
                    }
                }
                for cue in project.cues where (0..<4).contains(cue.track) {
                    let begin = cursor + Double(cue.start - frame) * scale
                    let end = cursor + Double(cue.end - frame) * scale
                    guard end >= 0, begin <= size.width else { continue }
                    let y = (Double(cue.track) + 0.5) * laneHeight
                    let role = project.roles.first { $0.id == cue.roleID }
                    let color = role.map(roleDisplayColor) ?? .black
                    var laneContext = context
                    laneContext.clip(to: Path(CGRect(x: 0, y: Double(cue.track) * laneHeight, width: size.width, height: laneHeight)))
                    for segment in Timeline.segments(cue) {
                        let x = cursor + Double(segment.start - frame) * scale
                        let segmentWidth = Double(segment.end - segment.start) * scale
                        guard segmentWidth > 0, x + segmentWidth >= 0, x <= size.width else { continue }
                        let text = laneContext.resolve(Text(segment.text).font(.custom(fontName, size: fontSize)).foregroundColor(color))
                        let measured = text.measure(in: CGSize(width: 100000, height: laneHeight))
                        guard measured.width > 0 else { continue }
                        var textContext = laneContext
                        textContext.translateBy(x: x, y: y + 2)
                        textContext.scaleBy(x: segmentWidth / measured.width, y: 1)
                        textContext.draw(text, at: .zero, anchor: .leading)
                    }
                    if showDetection {
                        let name = context.resolve(Text(role?.name ?? "Sans rôle").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                        let labelSize = name.measure(in: CGSize(width: 300, height: 14))
                        let labelX = begin - labelSize.width - 7
                        let labelY = Double(cue.track) * laneHeight
                        context.fill(Path(CGRect(x: labelX, y: labelY, width: labelSize.width + 6, height: 14)), with: .color(.black))
                        context.draw(name, at: CGPoint(x: labelX + 3, y: labelY + 7), anchor: .leading)
                    }
                    if showGrid {
                        for sign in cue.anchors {
                            let x = cursor + Double(sign.frame - frame) * scale
                            guard x >= 0, x <= size.width else { continue }
                            let bottom = Double(cue.track + 1) * laneHeight - 2
                            let color: Color = sign.kind.hasPrefix("in_") ? .green : sign.kind.hasPrefix("out_") ? .red : .black
                            var path = Path()
                            if sign.kind.hasPrefix("in_") || sign.kind.hasPrefix("out_") {
                                path.move(to: CGPoint(x: x, y: bottom - 14)); path.addLine(to: CGPoint(x: x - 5, y: bottom - 6))
                                path.addLine(to: CGPoint(x: x + 5, y: bottom - 6)); path.closeSubpath()
                                context.fill(path, with: .color(color))
                                context.fill(Path(CGRect(x: x - 1.5, y: bottom - 7, width: 3, height: 7)), with: .color(color))
                            } else {
                                path.move(to: CGPoint(x: x, y: bottom - 14)); path.addLine(to: CGPoint(x: x, y: bottom))
                                context.stroke(path, with: .color(color), lineWidth: 2)
                                context.draw(Text(sign.kind.uppercased()).font(.system(size: 7)).foregroundColor(.black), at: CGPoint(x: x + 3, y: bottom - 9), anchor: .leading)
                            }
                            if sign.id == selectedSign {
                                context.stroke(Path(CGRect(x: x - 7, y: bottom - 17, width: 14, height: 18)), with: .color(.blue), lineWidth: 1)
                            }
                        }
                    }
                }
                context.fill(Path(CGRect(x: cursor - 1, y: 0, width: 2, height: size.height)), with: .color(Color(red: 0.77, green: 0, blue: 0)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let track = min(3, max(0, Int(value.startLocation.y / laneHeight)))
                if !dragging {
                    dragging = true
                    dragReferenceFrame = frame
                    if showGrid {
                        for cue in project.cues where cue.track == track {
                            if let sign = cue.anchors.first(where: { abs(cursor + Double($0.frame - frame) * scale - value.startLocation.x) < 7 }) {
                                draggedSign = (cue.id, sign.id); dragSignFrame = sign.frame; break
                            }
                        }
                    }
                }
                let target = max(0, dragReferenceFrame + Int(((value.location.x - cursor) / scale).rounded()))
                if let (cueID, signID) = draggedSign {
                    moveSign(cueID, signID, max(0, dragSignFrame + Int((value.translation.width / scale).rounded())))
                }
                else { seek(target, track) }
            }.onEnded { _ in dragging = false; draggedSign = nil })
        }
        .clipped()
        .accessibilityLabel("Bande rythmo, quatre pistes, \(Timecode.format(frame, fps: project.framesPerSecond))")
    }
}
