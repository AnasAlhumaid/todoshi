import Foundation

/// Curated project color palette (hex strings, light-friendly; pair with semantic UI).
public enum ProjectColorCatalog: Sendable {
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
        Swatch(hex: "#5B8DEF", name: "Blue"),
        Swatch(hex: "#7C5CFC", name: "Indigo"),
        Swatch(hex: "#E85D75", name: "Rose"),
        Swatch(hex: "#F08C3A", name: "Orange"),
        Swatch(hex: "#E5B53A", name: "Gold"),
        Swatch(hex: "#3DBB7A", name: "Green"),
        Swatch(hex: "#2BB8C2", name: "Teal"),
        Swatch(hex: "#8E8E93", name: "Gray")
    ]

    public static let defaultHex = swatches[0].hex

    public static func sanitized(_ hex: String) -> String {
        let upper = hex.uppercased()
        return swatches.first(where: { $0.hex.uppercased() == upper })?.hex ?? defaultHex
    }
}
