import SwiftUI
import WidgetKit

extension View {
    func ascendWidgetSurface(_ theme: Theme?) -> some View {
        self.foregroundStyle(.white.opacity(0.78))
            .containerBackground(for: .widget) {
                ZStack {
                    Color(red: 0.065, green: 0.065, blue: 0.088)
                    LinearGradient(colors: [(theme ?? .shadow).accent.opacity(0.085), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
    }
}

/// Preserve the hue of data marks in accented widgets on supported desktops.
/// Labels and the widget surface still participate in the desktop appearance.
struct WidgetColorMark<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.displayScale) private var scale
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        let mark = content.frame(width: size.width, height: size.height)
        if #available(macOS 15, *), mode == .accented, let bitmap = snapshot(mark) {
            Image(decorative: bitmap, scale: scale)
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: size.width, height: size.height)
        } else {
            mark
        }
    }

    @MainActor private func snapshot(_ mark: some View) -> CGImage? {
        let renderer = ImageRenderer(content: mark.environment(\.colorScheme, .dark))
        renderer.scale = scale
        return renderer.cgImage
    }
}

struct WidgetSymbol: View {
    let name: String
    let theme: Theme
    var body: some View {
        WidgetColorMark(size: CGSize(width: 20, height: 20)) {
            Image(systemName: name).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent).shadow(color: theme.accent.opacity(0.4), radius: 2)
        }.accessibilityHidden(true)
    }
}
