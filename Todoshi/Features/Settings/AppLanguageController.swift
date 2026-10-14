import Foundation
import Observation
import SwiftUI
import TodoshiCore

/// Observable app-language preference for live locale + layoutDirection updates.
@Observable
@MainActor
final class AppLanguageController {
    private(set) var preference: AppLanguage

    init() {
        AppLanguageStore.migrateIfNeeded()
        preference = AppLanguageStore.preference()
    }

    var resolvedLocale: Locale { preference.resolvedLocale }

    var layoutDirection: LayoutDirection {
        preference.isRightToLeft ? .rightToLeft : .leftToRight
    }

    func select(_ language: AppLanguage) {
        guard language != preference else { return }
        AppLanguageStore.setPreference(language)
        preference = language
        NotificationCenter.default.post(name: .todoshiAppLanguageDidChange, object: language.rawValue)
    }
}

extension Notification.Name {
    static let todoshiAppLanguageDidChange = Notification.Name("todoshi.appLanguageDidChange")
}
