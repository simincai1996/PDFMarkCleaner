import SwiftUI

enum BackgroundTheme: String, CaseIterable, Identifiable {
    case frost
    case sky
    case mint
    case peach
    case sand

    var id: String { rawValue }

    var topColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.95, green: 0.97, blue: 1.0)
        case .sky:
            return Color(red: 0.92, green: 0.97, blue: 1.0)
        case .mint:
            return Color(red: 0.92, green: 0.99, blue: 0.97)
        case .peach:
            return Color(red: 0.99, green: 0.96, blue: 0.93)
        case .sand:
            return Color(red: 0.98, green: 0.97, blue: 0.92)
        }
    }

    var bottomColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.88, green: 0.93, blue: 0.98)
        case .sky:
            return Color(red: 0.86, green: 0.93, blue: 0.98)
        case .mint:
            return Color(red: 0.85, green: 0.96, blue: 0.93)
        case .peach:
            return Color(red: 0.98, green: 0.90, blue: 0.87)
        case .sand:
            return Color(red: 0.95, green: 0.93, blue: 0.86)
        }
    }

    var accentColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.36, green: 0.55, blue: 0.98)
        case .sky:
            return Color(red: 0.25, green: 0.63, blue: 0.98)
        case .mint:
            return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .peach:
            return Color(red: 0.97, green: 0.55, blue: 0.45)
        case .sand:
            return Color(red: 0.90, green: 0.65, blue: 0.35)
        }
    }
}
