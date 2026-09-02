import SwiftUI

enum NexusColor {
    /// Parses `#RRGGBB` (and optional `#AARRGGBB` ignored → RGB only).
    static func from(hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8 else {
            return Color.accentColor
        }
        if cleaned.count == 8 {
            cleaned = String(cleaned.suffix(6))
        }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}
