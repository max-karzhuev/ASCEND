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
        case .orange: Color(red: 1, green: 0.53, blue: 0.23)
        case .lemon: Color(red: 1, green: 0.90, blue: 0.35)
        case .lime: Color(red: 0.70, green: 0.91, blue: 0.27)
        case .mint: Color(red: 0.63, green: 0.96, blue: 0.77)
        case .cyan: Color(red: 0.25, green: 0.89, blue: 1)
        case .indigo: Color(red: 0.59, green: 0.59, blue: 1)
        case .rose: Color(red: 0.94, green: 0.44, blue: 0.57)
        case .coral: Color(red: 1, green: 0.53, blue: 0.47)
        case .silver: Color(red: 0.78, green: 0.82, blue: 0.88)
        case .ivory: Color(red: 0.97, green: 0.93, blue: 0.80)
        case .teal: Color(red: 0.25, green: 0.83, blue: 0.84)
        }
    }
    var deep: Color { accent.opacity(0.22) }
}
