import Foundation

/// In-app language preference. Missing/unknown storage always resolves to `.system` — never English.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    case system
    case arabic
    case english

    public var id: String { rawValue }

    /// Locale used for TodoshiL10n and SwiftUI environment. `.system` follows the device.
    public var resolvedLocale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .arabic:
            return Locale(identifier: "ar")
        case .english:
            return Locale(identifier: "en")
        }
    }

    /// Layout direction for the preference (system derives from the device locale).
    public var isRightToLeft: Bool {
        switch self {
        case .arabic:
            return true
        case .english:
            return false
        case .system:
            return Locale.autoupdatingCurrent.language.characterDirection == .rightToLeft
        }
    }
}

/// App Group–backed language preference shared by the app, widgets, and notification scheduling.
public enum AppLanguageStore: Sendable {
    public static let storageKey = "todoshi.appLanguage"

    /// Shared suite when available; falls back to standard defaults in unit tests without an App Group.
    public static func defaults(suiteName: String = AppGroupConstants.suiteName) -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Explicit user choice. Absent or invalid → `.system` (never invent English).
    public static func preference(in defaults: UserDefaults? = nil) -> AppLanguage {
        let store = defaults ?? Self.defaults()
        guard let raw = store.string(forKey: storageKey) else {
            return .system
        }
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// Persists an explicit Arabic/English override. `.system` removes the override key.
    public static func setPreference(_ language: AppLanguage, in defaults: UserDefaults? = nil) {
        let store = defaults ?? Self.defaults()
        switch language {
        case .system:
            store.removeObject(forKey: storageKey)
        case .arabic, .english:
            store.set(language.rawValue, forKey: storageKey)
        }
    }

    public static var resolvedLocale: Locale {
        preference().resolvedLocale
    }

    public static var isRightToLeft: Bool {
        preference().isRightToLeft
    }

    /// Safe migration: unknown legacy values become system. Does not invent an English preference.
    public static func migrateIfNeeded(in defaults: UserDefaults? = nil) {
        let store = defaults ?? Self.defaults()
        guard let raw = store.string(forKey: storageKey) else { return }
        if AppLanguage(rawValue: raw) == nil {
            store.removeObject(forKey: storageKey)
        }
    }
}

/// User-facing language picker copy.
public enum AppLanguagePresentation: Sendable {
    public static var sectionTitle: String {
        TodoshiL10n.tr("settings.language")
    }

    /// Compact row label inside the language section ("Language" / "اللغة").
    public static var rowLabel: String {
        TodoshiL10n.tr("settings.language.rowLabel")
    }

    public static var systemOption: String {
        TodoshiL10n.tr("settings.language.system")
    }

    /// Native language name — identical in EN/AR catalogs.
    public static var arabicOption: String {
        TodoshiL10n.tr("settings.language.arabic")
    }

    /// Native language name — identical in EN/AR catalogs.
    public static var englishOption: String {
        TodoshiL10n.tr("settings.language.english")
    }

    public static func title(for language: AppLanguage) -> String {
        switch language {
        case .system: return systemOption
        case .arabic: return arabicOption
        case .english: return englishOption
        }
    }
}
