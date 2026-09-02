import Foundation

/// Broadcast after successful SwiftData writes so the app can reload WidgetKit timelines.
public enum NexusDataChangeCenter {
    public static let notification = Notification.Name("com.anashamad.Nexus.dataDidChange")

    public static func post(_ event: WidgetReloadClassifier.Event) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [UserInfoKey.event: event.rawValue]
        )
    }

    public enum UserInfoKey {
        public static let event = "event"
    }

    public static func event(from userInfo: [AnyHashable: Any]?) -> WidgetReloadClassifier.Event? {
        guard let raw = userInfo?[UserInfoKey.event] as? String else { return nil }
        return WidgetReloadClassifier.Event(rawValue: raw)
    }
}
