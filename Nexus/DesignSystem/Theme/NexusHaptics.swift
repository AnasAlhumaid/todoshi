import UIKit

enum NexusHaptics {
    static func taskStatusChanged(crossStatus: Bool = true) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = crossStatus ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
