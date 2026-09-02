import SwiftUI
import NexusCore

struct WeekStripView: View {
    let summaries: [CalendarDaySummary]
    let selectedDate: Date
    let now: Date
    let calendar: Calendar
    var onSelect: (Date) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(summaries) { summary in
                weekDayCell(summary)
            }
        }
        .padding(.vertical, 4)
    }

    private func weekDayCell(_ summary: CalendarDaySummary) -> some View {
        let isSelected = calendar.isDate(summary.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(summary.date, inSameDayAs: now)
        let weekday = summary.date.formatted(.dateTime.weekday(.abbreviated))
        let day = calendar.component(.day, from: summary.date)

        return Button {
            onSelect(summary.date)
        } label: {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(day)")
                    .font(.body.weight(isSelected || isToday ? .bold : .regular).monospacedDigit())
                    .frame(width: 32, height: 32)
                    .background(circleFill(isSelected: isSelected, isToday: isToday))
                    .foregroundStyle(circleForeground(isSelected: isSelected, isToday: isToday))
                    .clipShape(Circle())

                taskDots(summary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekAccessibility(summary, isToday: isToday, isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func taskDots(_ summary: CalendarDaySummary) -> some View {
        HStack(spacing: 2) {
            if summary.openCount > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }
            if summary.overdueOpenCount > 0 {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
            } else if summary.completedCount > 0 && summary.openCount == 0 {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
            } else if !summary.hasTasks {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private func circleFill(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Color.accentColor }
        if isToday { return Color.accentColor.opacity(0.15) }
        return .clear
    }

    private func circleForeground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        return .primary
    }

    private func weekAccessibility(_ summary: CalendarDaySummary, isToday: Bool, isSelected: Bool) -> String {
        let dateText = summary.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        var parts = [dateText]
        if isToday { parts.append(CalendarStrings.today.lowercased()) }
        if isSelected { parts.append("selected") }
        parts.append(CalendarStrings.openTasks(summary.openCount))
        parts.append(CalendarStrings.completedTasks(summary.completedCount))
        if summary.overdueOpenCount > 0 {
            parts.append("\(summary.overdueOpenCount) overdue")
        }
        return parts.joined(separator: ", ")
    }
}
