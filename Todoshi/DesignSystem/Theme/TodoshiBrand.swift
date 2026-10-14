import SwiftUI

/// Todoshi brand palette — indigo / violet identity with semantic surfaces.
enum TodoshiBrand {
    static let accent = Color("AccentColor")
    static let accentSecondary = Color("BrandAccentSecondary")

    static var accentMuted: Color { accent.opacity(0.12) }
    static var accentSoft: Color { accent.opacity(0.18) }

    static var cardBackground: Color {
        adaptive(light: UIColor.white, dark: UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1))
    }
    static var elevatedSurface: Color { Color(.tertiarySystemGroupedBackground) }
    /// Page canvas with a faint indigo tint so cards lift off it.
    static var groupedBackground: Color {
        adaptive(
            light: UIColor(red: 0.965, green: 0.961, blue: 0.984, alpha: 1),
            dark: UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        )
    }

    static var secondaryText: Color { Color.secondary }
    static var border: Color { Color.primary.opacity(0.06) }
    static var borderStrong: Color { Color.primary.opacity(0.10) }

    /// Subtle card stroke for light and dark mode.
    static var cardStroke: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.06)
                : UIColor.clear
        })
    }

    /// Extra breathing room under the last card; the tab bar reserves its own safe-area inset.
    static let tabBarScrollInset: CGFloat = TodoshiSpacing.lg

    /// Very subtle card elevation (light mode only).
    static var cardShadow: Color {
        Color(red: 0.2, green: 0.18, blue: 0.45).opacity(0.07)
    }

    /// Faint wash of a project's color behind its card.
    static func projectWash(for colorHex: String) -> Color {
        TodoshiColor.from(hex: colorHex).opacity(0.05)
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Tinted icon well behind project glyphs on cards.
    static func iconWell(for colorHex: String) -> Color {
        TodoshiColor.from(hex: colorHex).opacity(0.14)
    }
}
