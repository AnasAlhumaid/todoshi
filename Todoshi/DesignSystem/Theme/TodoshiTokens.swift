import SwiftUI

enum NexusSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum NexusRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

enum NexusTypography {
    /// Large navigation / greeting.
    static let screenTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let section = Font.subheadline.weight(.semibold)
    static let primary = Font.body
    static let secondary = Font.subheadline
    static let metadata = Font.caption
    static let body = Font.body
    static let caption = Font.caption
}

enum NexusIconSize {
    static let glyph: CGFloat = 22
    static let row: CGFloat = 28
    static let hit: CGFloat = 44
}
