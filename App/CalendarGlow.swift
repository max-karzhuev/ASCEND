import SwiftUI

/// The fill, central highlight and light spilling past the tile animate together.
struct CalendarGlow: View, Animatable {
    var intensity: Double
    let accent: Color
    var cornerRadius: CGFloat = 7

    var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Bring the first completion into view while preserving every later increment.
        let light = pow(min(1, max(0, intensity)), 0.78)
        ZStack {
            tile.fill(accent.opacity(0.74 * light))
                .blur(radius: 2 + 4 * light)
            tile.fill(Color(white: 0.095))
            tile.fill(accent.opacity(0.76 * light))
            tile.fill(EllipticalGradient(colors: [accent, accent.opacity(0)],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.72))
                .opacity(0.88 * light)
            tile.fill(EllipticalGradient(colors: [.white, .clear],
                                         center: .center, startRadiusFraction: 0, endRadiusFraction: 0.56))
                .opacity(0.25 * light * light)
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct CalendarDateSquare<Label: View>: View {
    @ViewBuilder var label: Label

    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit).overlay { label }
    }
}
