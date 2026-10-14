import Foundation
import UserNotifications
import TodoshiCore

/// Routes notification taps through existing deep-link parsing.
final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate {
    var onOpenURL: ((URL) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let deepLinkRaw = info[NotificationUserInfoKey.deepLink] as? String
            ?? info[NotificationUserInfoKey.legacyDeepLink] as? String
        if let raw = deepLinkRaw,
           let url = URL(string: raw) {
            onOpenURL?(url)
        } else if let idRaw = info[NotificationUserInfoKey.taskID] as? String,
                  let id = UUID(uuidString: idRaw) {
            onOpenURL?(TodoshiDeepLink.task(id).url)
        }
        completionHandler()
    }
}
