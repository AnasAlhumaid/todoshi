import SwiftUI
import NexusCore

struct CalendarHeaderView: View {
    let mode: CalendarMode
    let selectedDate: Date
    let calendar: Calendar
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack {
            Button {
                onPrevious()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(CalendarStrings.previousPeriod)

            Spacer()

            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                if mode != .month {
                    Text(selectedDate, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(CalendarStrings.nextPeriod)
        }
        .overlay(alignment: .trailing) {
            // Today is in toolbar; keep header clean.
            EmptyView()
        }
    }

    private var title: String {
        switch mode {
        case .day:
            return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .week:
            let days = CalendarDatePolicy.weekDays(containing: selectedDate, calendar: calendar)
            guard let first = days.first, let last = days.last else {
                return selectedDate.formatted(.dateTime.month(.wide).year())
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return selectedDate.formatted(.dateTime.month(.wide).year())
        }
    }
}
