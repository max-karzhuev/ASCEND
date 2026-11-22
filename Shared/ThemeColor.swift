import SwiftUI

extension Theme {
    var accent: Color {
        switch self {
        case .shadow: Color(red: 0.70, green: 0.43, blue: 1)
        case .amber: Color(red: 1, green: 0.73, blue: 0.27)
        case .emerald: Color(red: 0.25, green: 0.86, blue: 0.63)
        case .crimson: Color(red: 1, green: 0.25, blue: 0.39)
        case .blue: Color(red: 0.32, green: 0.56, blue: 1)
        case .babyBlue: Color(red: 0.61, green: 0.84, blue: 1)
        case .pink: Color(red: 1, green: 0.52, blue: 0.76)
        case .lilac: Color(red: 0.83, green: 0.69, blue: 1)
        case .peach: Color(red: 1, green: 0.70, blue: 0.56)
        case .teal: Color(red: 0.25, green: 0.83, blue: 0.84)
        }
    }
    var deep: Color { accent.opacity(0.22) }
}
