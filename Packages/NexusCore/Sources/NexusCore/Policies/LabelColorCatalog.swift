import Foundation

/// Curated palette for labels (accessible accents; name still required in UI).
public enum LabelColorCatalog: Sendable {
    public struct Swatch: Sendable, Hashable, Identifiable {
        public let id: String
        public let hex: String
        public let name: String

        public init(hex: String, name: String) {
            self.id = hex
            self.hex = hex
            self.name = name
        }
    }

    public static let swatches: [Swatch] = [
        Swatch(hex: "#E85D75", name: "Rose"),
        Swatch(hex: "#F08C3A", name: "Orange"),
        Swatch(hex: "#E5B53A", name: "Gold"),
        Swatch(hex: "#3DBB7A", name: "Green"),
        Swatch(hex: "#2BB8C2", name: "Teal"),
        Swatch(hex: "#5B8DEF", name: "Blue"),
        Swatch(hex: "#7C5CFC", name: "Indigo"),
        Swatch(hex: "#C45CDA", name: "Violet"),
        Swatch(hex: "#8E8E93", name: "Gray"),
        Swatch(hex: "#6B7280", name: "Slate")
    ]

    public static let defaultHex = swatches[5].hex // Blue

    public static func sanitized(_ hex: String) -> String {
        let upper = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return swatches.first(where: { $0.hex.uppercased() == upper })?.hex ?? defaultHex
    }

    public static func name(for hex: String, locale: Locale = .autoupdatingCurrent) -> String {
        let upper = hex.uppercased()
        guard let swatch = swatches.first(where: { $0.hex.uppercased() == upper }) else {
            return NexusL10n.tr("label.generic", locale: locale)
        }
        return localizedColorName(hex: swatch.hex, locale: locale)
    }

    private static func localizedColorName(hex: String, locale: Locale) -> String {
        switch hex.uppercased() {
        case "#E85D75": return NexusL10n.tr("color.rose", locale: locale)
        case "#F08C3A": return NexusL10n.tr("color.orange", locale: locale)
        case "#E5B53A": return NexusL10n.tr("color.gold", locale: locale)
        case "#3DBB7A": return NexusL10n.tr("color.green", locale: locale)
        case "#2BB8C2": return NexusL10n.tr("color.teal", locale: locale)
        case "#5B8DEF": return NexusL10n.tr("color.blue", locale: locale)
        case "#7C5CFC": return NexusL10n.tr("color.indigo", locale: locale)
        case "#C45CDA": return NexusL10n.tr("color.violet", locale: locale)
        case "#8E8E93": return NexusL10n.tr("color.gray", locale: locale)
        case "#6B7280": return NexusL10n.tr("color.slate", locale: locale)
        default: return NexusL10n.tr("label.generic", locale: locale)
        }
    }
}
