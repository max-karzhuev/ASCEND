import SwiftUI

struct MuscleMap: View {
    @Environment(AppStore.self) private var store
    var planned: Set<MuscleGroup>
    var progress: [MuscleGroup: Double]
    @Binding var selected: MuscleGroup
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                figure("FRONT", parts: AnatomyGeometry.front)
                figure("BACK", parts: AnatomyGeometry.back)
            }.frame(maxWidth: 370).frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                Label("Planned today", systemImage: "circle.fill").foregroundStyle(store.profile.theme.accent)
                Label("Weekly progress", systemImage: "circle.lefthalf.filled").foregroundStyle(Palette.muted)
            }.font(.caption2)
        }.padding(.vertical, 4)
    }
    private func figure(_ title: String, parts: [AnatomyPart]) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
            AnatomicalFigure(parts: parts, planned: planned, progress: progress, selected: $selected)
                .aspectRatio(AnatomyGeometry.aspectRatio, contentMode: .fit)
                .frame(maxHeight: 300)
        }
    }
}
private struct AnatomicalFigure: View {
    @Environment(AppStore.self) private var store
    var parts: [AnatomyPart]
    var planned: Set<MuscleGroup>
    var progress: [MuscleGroup: Double]
    @Binding var selected: MuscleGroup
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let transform = CGAffineTransform(scaleX: size.width, y: size.height)
                for part in parts {
                    let path = part.path.applying(transform)
                    let amount = min(1, max(0, part.muscle.flatMap { progress[$0] } ?? 0))
                    let lit = part.muscle.map { planned.contains($0) } ?? false
                    let focus = part.muscle == selected
                    let fill = lit ? store.profile.theme.accent.opacity(0.22 + 0.52 * amount) : Color(white: 0.035 + amount * 0.19)
                    context.fill(path, with: .color(fill))
                    context.stroke(path, with: .color(lit ? store.profile.theme.accent.opacity(focus ? 1 : 0.8) : focus ? store.profile.theme.accent.opacity(0.65) : Color.white.opacity(0.24)), lineWidth: focus ? 1.05 : 0.65)
                }
            }.contentShape(Rectangle())
                .onTapGesture { location in select(at: location, size: geometry.size) }
        }.accessibilityHidden(true) // The labelled muscle selector below supplies 44-point VoiceOver controls.
    }
    private func select(at location: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let point = CGPoint(x: location.x / size.width, y: location.y / size.height)
        let available = parts.filter { $0.muscle != nil }
        if let direct = available.first(where: { $0.path.contains(point) }), let muscle = direct.muscle { selected = muscle; return }
        // Expand nearby touch capture to a 44-point diameter without overlapping invisible buttons.
        let nearby = available.compactMap { part -> (MuscleGroup, CGFloat)? in
            guard let muscle = part.muscle else { return nil }
            let rect = part.path.boundingRect.applying(CGAffineTransform(scaleX: size.width, y: size.height))
            let dx = max(rect.minX - location.x, 0, location.x - rect.maxX)
            let dy = max(rect.minY - location.y, 0, location.y - rect.maxY)
            let distance = hypot(dx, dy)
            return distance <= 22 ? (muscle, distance) : nil
        }.min { $0.1 < $1.1 }
        if let nearby { selected = nearby.0 }
    }
}
struct AnatomyPart: Identifiable {
    let id: String
    let muscle: MuscleGroup?
    let path: Path
    init(id: String, muscle: MuscleGroup?, encoded: String) {
        self.id = id; self.muscle = muscle
        let tokens = encoded.split(separator: " ")
        var index = 0, path = Path()
        func point() -> CGPoint {
            let x = Double(tokens[index])!, y = Double(tokens[index + 1])!; index += 2
            return CGPoint(x: x, y: y)
        }
        // Generated, bundled data uses only absolute M/L/C/Q/Z commands; never parses external input.
        while index < tokens.count {
            let command = tokens[index]; index += 1
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C": let first = point(), second = point(), end = point(); path.addCurve(to: end, control1: first, control2: second)
            case "Q": let control = point(), end = point(); path.addQuadCurve(to: end, control: control)
            case "Z": path.closeSubpath()
            default: preconditionFailure("Invalid bundled anatomy path")
            }
        }
        self.path = path
    }
}
