import SwiftUI

enum Palette {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.055)
    static let surface = Color(red: 0.070, green: 0.069, blue: 0.092)
    static let raised = Color(red: 0.095, green: 0.092, blue: 0.125)
    static let muted = Color(red: 0.64, green: 0.63, blue: 0.72)
    static let border = Color.white.opacity(0.085)
    static let radius: CGFloat = 18
}
struct AscendMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY * 0.69))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        p.move(to: CGPoint(x: r.midX, y: r.height * 0.37))
        p.addLine(to: CGPoint(x: r.width * 0.35, y: r.height * 0.77))
        p.addLine(to: CGPoint(x: r.midX, y: r.height * 0.63))
        p.addLine(to: CGPoint(x: r.width * 0.65, y: r.height * 0.77))
        p.closeSubpath(); return p
    }
}
struct Brand: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        HStack(spacing: 11) {
            AscendMark().fill(store.profile.theme.accent, style: FillStyle(eoFill: true)).frame(width: 27, height: 27)
            Text("ASCEND").font(.system(.title3, design: .rounded, weight: .bold)).tracking(1.6)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Ascend")
    }
}
struct Card<Content: View>: View {
    var padding: CGFloat = 22
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.raised.opacity(0.72), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: Palette.radius))
            .overlay(RoundedRectangle(cornerRadius: Palette.radius).stroke(Palette.border, lineWidth: 1).allowsHitTesting(false))
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(.system(.caption2, design: .monospaced, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted) }
}
extension View {
    func buttonTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
struct TargetButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.buttonTarget().opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
struct AccentButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 12)
            .buttonTarget()
            .foregroundStyle(Color.black.opacity(0.88)).background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.18), lineWidth: 1).allowsHitTesting(false))
            .opacity(enabled ? 1 : 0.4)
    }
}
struct Meter: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.065))
                Capsule().fill(LinearGradient(colors: [store.profile.theme.accent.opacity(0.65), store.profile.theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, value)))
            }
        }.frame(height: height).animation(reduceMotion || store.profile.reducedMotion ? nil : .easeOut(duration: 0.3), value: value)
            .accessibilityLabel("Progress").accessibilityValue("\(Int(value * 100)) percent")
    }
}
struct EmptyCard: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(store.profile.theme.accent).padding(.bottom, 3)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(TargetButton()).tint(store.profile.theme.accent) }
        }.frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 12)
    }
}
struct ScreenHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
}
struct PageScroll<Content: View>: View {
    @Environment(AppStore.self) private var store
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.isValidation { ValidationBanner() }
                content
            }
            #if os(iOS)
            .padding(16)
            #else
            .padding(24)
            #endif
            .frame(maxWidth: 1240).frame(maxWidth: .infinity)
        }.background(Palette.background)
    }
}
struct ValidationBanner: View {
    var body: some View { Text("VALIDATION WORKSPACE · Separate test history").font(.caption2.monospaced()).foregroundStyle(.yellow).fixedSize(horizontal: false, vertical: true) }
}
struct StatusLabel: View {
    var text: String
    var icon: String = "externaldrive"
    var body: some View { Label(text, systemImage: icon).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
}
extension View {
    func editorFrame() -> some View {
        self.frame(idealWidth: 560, idealHeight: 650)
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 480)
            #endif
    }
}
