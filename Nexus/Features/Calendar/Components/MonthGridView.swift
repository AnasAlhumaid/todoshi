import SwiftUI
import NexusCore

struct MonthDayCell: View {
    let cell: CalendarMonthCell
    let isSelected: Bool
    let isToday: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                Text(dayLabel)
                    .font(.footnote.weight(isSelected || isToday ? .bold : .regular).monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(background)
                    .foregroundStyle(foreground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                indicator
                    .frame(height: 6)
            }
        }
        .buttonStyle(.plain)
        .disabled(cell.date == nil)
        .opacity(cell.isInMonth ? 1 : 0.35)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(CalendarStrings.selectDate)
    }

    private var dayLabel: String {
        if let n = cell.dayNumber { return "\(n)" }
        return " "
    }

    private var background: Color {
        if isSelected { return .accentColor }
        if isToday { return Color.accentColor.opacity(0.18) }
        return .clear
    }

    private var foreground: Color {
        if isSelected { return .white }
        return .primary
    }

    @ViewBuilder
    private var indicator: some View {
        if let summary = cell.summary, summary.hasTasks {
            HStack(spacing: 2) {
                if summary.openCount > 0 {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                }
                if summary.overdueOpenCount > 0 {
                    Circle().fill(Color.red).frame(width: 4, height: 4)
                } else if summary.completedCount > 0 {
                    Circle().fill(Color.secondary.opacity(0.45)).frame(width: 4, height: 4)
                }
            }
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        guard let date = cell.date, let summary = cell.summary else {
            return NexusL10n.tr("calendar.a11yEmpty")
        }
        let dateText = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        var parts = [dateText]
        if isToday { parts.append(CalendarStrings.today.lowercased()) }
        if isSelected { parts.append(NexusL10n.tr("calendar.a11ySelected")) }
        parts.append(CalendarStrings.openTasks(summary.openCount))
        parts.append(CalendarStrings.completedTasks(summary.completedCount))
        if summary.overdueOpenCount > 0 {
            parts.append(NexusL10n.tr("calendar.a11yOverdueTasks"))
        }
        return parts.joined(separator: ", ")
    }
}

struct MonthGridView: View {
    let cells: [CalendarMonthCell]
    let selectedDate: Date
    let now: Date
    let calendar: Calendar
    var onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            weekdayHeaders
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    MonthDayCell(
                        cell: cell,
                        isSelected: cell.date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false,
                        isToday: cell.date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                    ) {
                        if let date = cell.date {
                            onSelect(date)
                        }
                    }
                }
            }
        }
    }

    private var weekdayHeaders: some View {
        let symbols = calendar.shortWeekdaySymbols
        // shortWeekdaySymbols are Sunday-first index 0; reorder by firstWeekday
        let ordered = (0..<7).map { offset -> String in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return symbols[index]
        }
        return HStack(spacing: 4) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
