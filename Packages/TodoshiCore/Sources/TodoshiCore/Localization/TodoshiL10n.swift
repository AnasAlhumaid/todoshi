import Foundation

/// Locale-aware string access for TodoshiCore (String Catalog in module resources).
///
/// Xcode app builds can resolve catalogs via Foundation. SPM package tests often ship the raw
/// `.xcstrings` file, so this helper also reads the catalog JSON from `Bundle.module`.
public enum TodoshiL10n: Sendable {
    public static func tr(_ key: String, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        resolve(key: key, locale: locale, count: nil)
    }

    public static func format(
        _ key: String,
        locale: Locale = AppLanguageStore.resolvedLocale,
        _ arguments: CVarArg...
    ) -> String {
        let template = resolve(key: key, locale: locale, count: nil)
        return String(format: template, locale: locale, arguments: arguments)
    }

    /// Resolves a pluralized catalog entry (String Catalog plural variations).
    public static func plural(
        _ key: String,
        count: Int,
        locale: Locale = AppLanguageStore.resolvedLocale
    ) -> String {
        let template = catalogValue(key: key, locale: locale, count: count)
            ?? resolve(key: key, locale: locale, count: nil)
        // Pass count as a direct CVarArg — packing `[count]` often fails to format.
        return String(format: template, locale: locale, count)
    }

    private static func resolve(key: String, locale: Locale, count: Int?) -> String {
        if let catalog = catalogValue(key: key, locale: locale, count: count) {
            return catalog
        }
        if let bundled = bundleLocalizedValue(key: key, locale: locale) {
            return bundled
        }
        return String(localized: String.LocalizationValue(key), bundle: .module, locale: locale)
    }

    public static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, table: "Localizable", bundle: .atURL(Bundle.module.bundleURL))
    }

    // MARK: - Catalog JSON

    private static let catalogLock = NSLock()
    private static var cachedRoot: [String: Any]?

    private static func catalogValue(key: String, locale: Locale, count: Int?) -> String? {
        guard let strings = catalogRoot()?["strings"] as? [String: Any],
              let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any] else {
            return nil
        }

        for id in localeCandidates(for: locale) {
            guard let loc = localizations[id] as? [String: Any] else { continue }
            if let value = stringUnitValue(loc) {
                return value
            }
            if let variations = loc["variations"] as? [String: Any],
               let plural = variations["plural"] as? [String: Any] {
                let category = pluralCategory(count: count ?? 1, language: id)
                for form in [category, "other", "one", "many", "few", "two", "zero"] {
                    if let formEntry = plural[form] as? [String: Any],
                       let value = stringUnitValue(formEntry) {
                        return value
                    }
                }
            }
        }
        return nil
    }

    private static func stringUnitValue(_ node: [String: Any]) -> String? {
        if let unit = node["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String {
            return value
        }
        if let value = node["value"] as? String {
            return value
        }
        return nil
    }

  /// Language identifiers to try for catalog JSON and compiled `.lproj` bundles.
    private static func localeCandidates(for locale: Locale) -> [String] {
        var ids: [String] = []
        if let language = locale.language.languageCode?.identifier {
            ids.append(language)
        }
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if !normalized.isEmpty {
            ids.append(normalized)
            if let base = normalized.split(separator: "-").first.map(String.init) {
                ids.append(base)
            }
        }
        // System preference uses `.autoupdatingCurrent`; ensure the live device language is tried.
        if locale == .autoupdatingCurrent,
           let deviceLanguage = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            ids.append(deviceLanguage)
        }
        ids.append("en")
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Resolves via compiled `ar.lproj` / `en.lproj` bundles (device/Xcode builds).
    /// SPM tests may ship the raw `.xcstrings` file instead; catalog JSON handles that path.
    private static func bundleLocalizedValue(key: String, locale: Locale) -> String? {
        let bundle = Bundle.module
        for languageID in localeCandidates(for: locale) {
            guard let lprojPath = bundle.path(forResource: languageID, ofType: "lproj"),
                  let localizedBundle = Bundle(path: lprojPath) else {
                continue
            }
            let value = localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if value != key {
                return value
            }
        }
        return nil
    }

    private static func pluralCategory(count: Int, language: String) -> String {
        let lang = language.split(separator: "-").first.map(String.init)?.lowercased() ?? language.lowercased()
        if lang == "ar" {
            switch abs(count) {
            case 0: return "zero"
            case 1: return "one"
            case 2: return "two"
            case 3...10: return "few"
            case 11...99: return "many"
            default: return "other"
            }
        }
        return abs(count) == 1 ? "one" : "other"
    }

    private static func catalogRoot() -> [String: Any]? {
        catalogLock.lock()
        defer { catalogLock.unlock() }
        if let cachedRoot { return cachedRoot }
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            cachedRoot = [:]
            return cachedRoot
        }
        cachedRoot = json
        return cachedRoot
    }
}
