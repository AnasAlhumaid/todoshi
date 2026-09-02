import Foundation

/// Curated SF Symbols for project icons (MVP).
public enum ProjectIconCatalog: Sendable {
    public static let symbols: [String] = [
        "folder.fill",
        "shippingbox.fill",
        "hammer.fill",
        "desktopcomputer",
        "iphone",
        "server.rack",
        "globe",
        "app.fill",
        "terminal.fill",
        "paintbrush.fill",
        "gearshape.2.fill",
        "bolt.fill",
        "star.fill",
        "bookmark.fill",
        "doc.text.fill",
        "chart.bar.fill"
    ]

    public static let defaultSymbol = "folder.fill"

    public static func sanitized(_ symbol: String) -> String {
        symbols.contains(symbol) ? symbol : defaultSymbol
    }
}
