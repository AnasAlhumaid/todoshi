import Foundation
import Testing
@testable import TodoshiCore

struct AppLanguagePreferenceTests {
    private func isolatedDefaults() -> UserDefaults {
        let name = "todoshi.language.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Missing preference defaults to system, not English")
    func missingDefaultsToSystem() {
        let defaults = isolatedDefaults()
        #expect(AppLanguageStore.preference(in: defaults) == .system)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == nil)
    }

    @Test("Unknown stored value migrates to system")
    func unknownMigratesToSystem() {
        let defaults = isolatedDefaults()
        defaults.set("french", forKey: AppLanguageStore.storageKey)
        AppLanguageStore.migrateIfNeeded(in: defaults)
        #expect(AppLanguageStore.preference(in: defaults) == .system)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == nil)
    }

    @Test("Explicit Arabic and English persist; System clears override")
    func explicitPersistAndClear() {
        let defaults = isolatedDefaults()
        AppLanguageStore.setPreference(.arabic, in: defaults)
        #expect(AppLanguageStore.preference(in: defaults) == .arabic)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == "arabic")
        #expect(AppLanguage.arabic.resolvedLocale.language.languageCode?.identifier == "ar")
        #expect(AppLanguage.arabic.isRightToLeft)

        AppLanguageStore.setPreference(.english, in: defaults)
        #expect(AppLanguageStore.preference(in: defaults) == .english)
        #expect(AppLanguage.english.resolvedLocale.language.languageCode?.identifier == "en")
        #expect(!AppLanguage.english.isRightToLeft)

        AppLanguageStore.setPreference(.system, in: defaults)
        #expect(AppLanguageStore.preference(in: defaults) == .system)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == nil)
    }

    @Test("Language picker copy resolves in Arabic and English")
    func presentationCopy() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(TodoshiL10n.tr("settings.language", locale: en) == "App Language")
        #expect(TodoshiL10n.tr("settings.language.system", locale: en) == "System Language")
        #expect(TodoshiL10n.tr("settings.language", locale: ar) == "لغة التطبيق")
        #expect(TodoshiL10n.tr("settings.language.system", locale: ar) == "لغة الجهاز")
        #expect(TodoshiL10n.tr("settings.language.arabic", locale: en) == "العربية")
        #expect(TodoshiL10n.tr("settings.language.english", locale: ar) == "English")
    }

    @Test("Reminder due format localizes")
    func reminderDueFormat() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        let enBody = TodoshiL10n.format("notification.reminderDue", locale: en, "Home", "Aug 27")
        let arBody = TodoshiL10n.format("notification.reminderDue", locale: ar, "البيت", "٢٧ أغسطس")
        #expect(enBody.contains("Due"))
        #expect(arBody.contains("مستحقة"))
    }

    @Test("Explicit Arabic preference resolves Arabic status copy via store locale")
    func storeLocaleFeedsL10n() {
        let defaults = isolatedDefaults()
        AppLanguageStore.setPreference(.arabic, in: defaults)
        // Direct locale path (widgets/notifications pass resolved locale).
        #expect(TaskStatus.todo.displayName(locale: AppLanguage.arabic.resolvedLocale) == "جاهزة للبدء")
        #expect(TaskStatus.done.displayName(locale: AppLanguage.english.resolvedLocale) == "Done")
    }

    @Test("Do not overwrite an explicit English choice during migration")
    func preservesExplicitEnglish() {
        let defaults = isolatedDefaults()
        AppLanguageStore.setPreference(.english, in: defaults)
        AppLanguageStore.migrateIfNeeded(in: defaults)
        #expect(AppLanguageStore.preference(in: defaults) == .english)
        #expect(defaults.string(forKey: AppLanguageStore.storageKey) == "english")
    }

    @Test("Arabic preference resolves Arabic settings strings via default locale")
    func arabicPreferenceResolvesArabicStrings() {
        let ar = AppLanguage.arabic.resolvedLocale
        #expect(TodoshiL10n.tr("settings.title", locale: ar) == "الإعدادات")
        #expect(TodoshiL10n.tr("tab.dashboard", locale: ar) == "الرئيسية")
        #expect(TodoshiL10n.tr("tab.calendar", locale: ar) == "التقويم")
        #expect(TodoshiL10n.tr("tab.search", locale: ar) == "البحث")
        #expect(TodoshiL10n.tr("settings.organization", locale: ar) == "التنظيم")
        #expect(TodoshiL10n.tr("label.labels", locale: ar) == "التصنيفات")
        #expect(TodoshiL10n.tr("settings.notifications", locale: ar) == "الإشعارات")
    }

    @Test("English preference resolves English settings strings via default locale")
    func englishPreferenceResolvesEnglishStrings() {
        let en = AppLanguage.english.resolvedLocale
        #expect(TodoshiL10n.tr("settings.title", locale: en) == "Settings")
        #expect(TodoshiL10n.tr("tab.dashboard", locale: en) == "Home")
        #expect(TodoshiL10n.tr("settings.language.rowLabel", locale: en) == "Language")
    }

    @Test("Preference display label shows stored choice, not resolved device language")
    func preferenceDisplayLabels() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(AppLanguagePresentation.title(for: .system) == TodoshiL10n.tr("settings.language.system", locale: en))
        #expect(AppLanguagePresentation.title(for: .arabic) == TodoshiL10n.tr("settings.language.arabic", locale: en))
        #expect(AppLanguagePresentation.title(for: .english) == TodoshiL10n.tr("settings.language.english", locale: en))
        #expect(AppLanguagePresentation.rowLabel == TodoshiL10n.tr("settings.language.rowLabel", locale: en))
        #expect(TodoshiL10n.tr("settings.language.rowLabel", locale: ar) == "اللغة")
    }

    @Test("Arabic and English bundle lookup resolves known keys")
    func bundleLookupResolvesKnownKeys() {
        let ar = Locale(identifier: "ar")
        let en = Locale(identifier: "en")
        #expect(TodoshiL10n.tr("account.section", locale: ar) == "الحساب")
        #expect(TodoshiL10n.tr("account.section", locale: en) == "Account")
    }

    @Test("RTL follows preference independently of string resolution")
    func rtlFollowsPreference() {
        #expect(AppLanguage.arabic.isRightToLeft)
        #expect(!AppLanguage.english.isRightToLeft)
    }
}
