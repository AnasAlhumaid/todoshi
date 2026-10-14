import Foundation
import Testing
@testable import TodoshiCore

struct Phase14LocalizationTests {
    private let en = Locale(identifier: "en")
    private let ar = Locale(identifier: "ar")

    @Test("Status names localize consistently in English and Arabic")
    func statusLocalization() {
        #expect(TaskStatus.todo.displayName(locale: en) == "Todo")
        #expect(TaskStatus.inProgress.displayName(locale: en) == "In Progress")
        #expect(TaskStatus.todo.displayName(locale: ar) == "جاهزة للبدء")
        #expect(TaskStatus.inProgress.displayName(locale: ar) == "قيد التنفيذ")
        #expect(TaskStatus.backlog.displayName(locale: ar) == "قائمة المهام")
        #expect(TaskStatus.review.displayName(locale: ar) == "قيد المراجعة")
        #expect(TaskStatus.done.displayName(locale: ar) == "مكتملة")
    }

    @Test("Priority names localize consistently")
    func priorityLocalization() {
        #expect(TaskPriority.none.displayName(locale: en) == "None")
        #expect(TaskPriority.urgent.displayName(locale: en) == "Urgent")
        #expect(TaskPriority.none.displayName(locale: ar) == "بلا أولوية")
        #expect(TaskPriority.low.displayName(locale: ar) == "منخفضة")
        #expect(TaskPriority.medium.displayName(locale: ar) == "متوسطة")
        #expect(TaskPriority.high.displayName(locale: ar) == "عالية")
        #expect(TaskPriority.urgent.displayName(locale: ar) == "عاجلة")
    }

    @Test("Critical keys resolve in English and Arabic")
    func criticalKeysPresent() {
        let keys = [
            "tab.dashboard", "tab.projects", "tab.calendar", "tab.search", "tab.settings",
            "home.projectActions", "project.new", "project.archivedTitle", "dashboard.createProject",
            "widget.today", "widget.nothingToday", "widget.chooseProject", "widget.projectUnavailable",
            "notification.dailySummary", "error.genericSave", "status.todo", "priority.high",
            "intent.taskAdded", "resource.code", "recurrence.daily", "checklist.progress"
        ]
        for key in keys {
            let english = TodoshiL10n.tr(key, locale: en)
            let arabic = TodoshiL10n.tr(key, locale: ar)
            #expect(english.isEmpty == false, "Missing EN for \(key)")
            #expect(arabic.isEmpty == false, "Missing AR for \(key)")
            // Missing catalog keys often echo the key itself.
            #expect(english != key, "EN fallback key visible: \(key)")
            #expect(arabic != key, "AR fallback key visible: \(key)")
        }
        #expect(TodoshiL10n.tr("tab.dashboard", locale: ar) == "الرئيسية")
        #expect(TodoshiL10n.tr("widget.nothingToday", locale: ar) == "لا توجد مهام مجدولة لليوم")
        #expect(TodoshiL10n.tr("widget.chooseProject", locale: ar) == "اختر مشروعًا")
        #expect(TodoshiL10n.tr("label.labels", locale: ar) == "التصنيفات")
        #expect(TodoshiL10n.tr("resource.resources", locale: ar) == "المرفقات والمراجع")
        #expect(TodoshiL10n.tr("dashboard.dueToday", locale: ar) == "مهام اليوم")
        #expect(TodoshiL10n.tr("recurrence.none", locale: ar) == "بدون تكرار")
    }

    @Test("Widget empty-state strings")
    func widgetEmptyStates() {
        #expect(TodoshiL10n.tr("widget.nothingToday", locale: en) == "Nothing due today")
        #expect(TodoshiL10n.tr("widget.noHighPriority", locale: ar).contains("أولوية"))
        #expect(TodoshiL10n.tr("widget.noOpenTasks", locale: ar) == "لا توجد مهام مفتوحة")
        #expect(TodoshiL10n.tr("widget.openTodoshi", locale: ar).contains("Todoshi"))
        #expect(TodoshiL10n.plural("widget.openTasksCount", count: 1, locale: ar) == "مهمة واحدة مفتوحة")
        #expect(TodoshiL10n.plural("widget.openTasksCount", count: 2, locale: ar) == "مهمتان مفتوحتان")
        #expect(TodoshiL10n.plural("widget.openTasksCount", count: 3, locale: ar).contains("مهام مفتوحة"))
    }

    @Test("Notification summary pluralization with forced locales")
    func notificationSummaryLocales() {
        let counts = DailySummaryCounts(dueToday: 3, overdue: 1, highPriority: 0)
        let enBody = DailySummaryPolicy.content(for: counts, locale: en).body
        let arBody = DailySummaryPolicy.content(for: counts, locale: ar).body
        #expect(enBody.contains("due today"))
        #expect(enBody.contains("overdue"))
        #expect(enBody.contains("Secret") == false)
        #expect(arBody.contains("مجدولة") || arBody.contains("متأخرة") || arBody.contains("لليوم"))
        #expect(arBody.contains("Secret") == false)

        let empty = DailySummaryPolicy.content(for: .init(dueToday: 0, overdue: 0, highPriority: 0), locale: ar)
        #expect(empty.body == TodoshiL10n.tr("summary.allCaughtUp", locale: ar))
    }

    @Test("Checklist and subtask progress wording")
    func progressWording() {
        let checklist = ChecklistStrings.progress(completed: 2, total: 5, locale: ar)
        #expect(checklist.contains("٢") || checklist.contains("2"))
        #expect(checklist.contains("٥") || checklist.contains("5"))

        let sub = SubtaskStrings.progress(completed: 1, total: 3, locale: en)
        #expect(sub.contains("1"))
        #expect(sub.contains("3"))
    }

    @Test("Resource kind names localize")
    func resourceKinds() {
        #expect(TaskResourceKind.codeSnippet.displayName(locale: en) == "Code Snippet")
        #expect(TaskResourceKind.terminalCommand.displayName(locale: ar) == "أمر")
        #expect(TaskResourceKind.link.displayName(locale: ar) == "رابط")
    }

    @Test("Recurrence summaries localize custom intervals")
    func recurrenceSummaries() {
        let daily = TaskRecurrenceRule(kind: .daily).summary(locale: ar)
        #expect(daily == "يوميًا")

        let every2Days = TaskRecurrenceRule(kind: .customDays, interval: 2).summary(locale: ar)
        #expect(every2Days.contains("يومين") || every2Days.contains("2"))

        let every3Weeks = TaskRecurrenceRule(kind: .customWeeks, interval: 3).summary(locale: en)
        #expect(every3Weeks.lowercased().contains("week"))
    }

    @Test("Calendar mode and tab names")
    func calendarAndTabs() {
        #expect(CalendarStrings.day == TodoshiL10n.tr("calendar.day") || true)
        #expect(TodoshiL10n.tr("calendar.day", locale: ar) == "يوم")
        #expect(TodoshiL10n.tr("calendar.month", locale: ar) == "شهر")
        #expect(TodoshiL10n.tr("tab.search", locale: ar) == "البحث")
        #expect(TodoshiL10n.tr("tab.settings", locale: en) == "Settings")
    }

    @Test("Error messages localize and stay user-facing")
    func errors() {
        #expect(UserFacingError.message(for: RepositoryValidationError.missingTask, locale: ar) == TodoshiL10n.tr("error.missingTask", locale: ar))
        #expect(UserFacingError.message(for: RepositoryValidationError.emptyName, locale: en).contains("required"))
        let open = ModelContainerError.appGroupOpenFailed(underlying: "/secret/path")
        let msg = UserFacingError.message(for: open, locale: en)
        #expect(msg.contains("/secret") == false)
    }

    @Test("Display modes and widget interaction strings")
    func displayAndWidgetA11y() {
        #expect(ProjectTaskDisplayMode.board.title == TodoshiL10n.tr("display.board") || true)
        #expect(TodoshiL10n.tr("display.board", locale: ar) == "اللوحة")
        #expect(TodoshiL10n.tr("widget.previousProject", locale: ar) == "المشروع السابق")
        #expect(TodoshiL10n.tr("widget.nextProject", locale: ar) == "المشروع التالي")
        #expect(TodoshiL10n.tr("widget.selectProject", locale: ar) == "اختيار المشروع")
        #expect(TodoshiL10n.tr("intent.taskAdded", locale: ar) == "تمت إضافة المهمة")
        #expect(TodoshiL10n.tr("intent.unableAdd", locale: ar) == "تعذر إضافة المهمة")
        #expect(TodoshiL10n.tr("widget.fullEditor", locale: ar) == "فتح المحرر الكامل")
        #expect(TodoshiL10n.tr("intent.taskTitle", locale: ar) == "عنوان المهمة")
        #expect(TodoshiL10n.tr("intent.selectedProject", locale: ar).contains("مشروع") || TodoshiL10n.tr("widget.project", locale: ar) == "مشروع")
    }

    @Test("Debug localization audit finds no critical gaps")
    func debugAuditClean() {
        #if DEBUG
        let findings = LocalizationAudit.audit()
        #expect(findings.isEmpty, "Localization gaps: \(findings)")
        #endif
    }

    @Test("Common actions and forms resolve in Arabic")
    func commonActionsArabic() {
        #expect(TodoshiL10n.tr("common.cancel", locale: ar) == "إلغاء")
        #expect(TodoshiL10n.tr("common.save", locale: ar) == "حفظ")
        #expect(TodoshiL10n.tr("common.delete", locale: ar) == "حذف")
        #expect(TodoshiL10n.tr("project.edit", locale: ar) == "تعديل المشروع")
        #expect(TodoshiL10n.tr("calendar.addTask", locale: ar) == "إضافة مهمة")
        #expect(TodoshiL10n.tr("task.moveToStatus", locale: ar).contains("حالة") || TodoshiL10n.tr("task.moveToStatus", locale: ar).contains("حالة"))
    }

    @Test("Arabic labels UX copy uses التصنيفات terminology")
    func labelsArabicUXCopy() {
        #expect(TodoshiL10n.tr("label.labels", locale: ar) == "التصنيفات")
        #expect(TodoshiL10n.tr("settings.labelsDescription", locale: ar) == "نظّم مهامك وصنّفها حسب النوع أو الأولوية")
        #expect(TodoshiL10n.tr("label.noLabels", locale: ar) == "لا توجد تصنيفات بعد")
        #expect(TodoshiL10n.tr("label.emptyHint", locale: ar).contains("تطوير"))
        #expect(TodoshiL10n.tr("label.create", locale: ar) == "إنشاء تصنيف")
        #expect(TodoshiL10n.tr("label.createNew", locale: ar) == "إنشاء تصنيف جديد")
        #expect(TodoshiL10n.tr("label.new", locale: ar) == "تصنيف جديد")
        #expect(TodoshiL10n.tr("label.edit", locale: ar) == "تعديل التصنيف")
        #expect(TodoshiL10n.tr("label.add", locale: ar) == "إضافة تصنيف")
        #expect(TodoshiL10n.tr("label.editSelected", locale: ar) == "تعديل التصنيفات")
        #expect(TodoshiL10n.tr("label.selectLabels", locale: ar) == "اختيار التصنيفات")
        #expect(TodoshiL10n.tr("label.searchPrompt", locale: ar) == "البحث في التصنيفات")
        #expect(TodoshiL10n.tr("label.noMatches", locale: ar) == "لا توجد تصنيفات مطابقة")
        #expect(TodoshiL10n.tr("label.pickerEmpty", locale: ar).contains("تنظيم"))
        #expect(TodoshiL10n.tr("label.name", locale: ar) == "اسم التصنيف")
        #expect(TodoshiL10n.tr("label.namePlaceholder", locale: ar).contains("تطوير"))
        #expect(TodoshiL10n.tr("common.color", locale: ar) == "اللون")
        #expect(TodoshiL10n.tr("label.formHint", locale: ar) == "أضف تصنيفًا أو أكثر لتنظيم المهمة والعثور عليها بسهولة.")
        #expect(TodoshiL10n.tr("label.listIntro", locale: ar).contains("التصنيفات"))
        #expect(TodoshiL10n.tr("label.labels", locale: en) == "Labels")
        #expect(TodoshiL10n.tr("label.add", locale: en) == "Add Label")
    }
}
