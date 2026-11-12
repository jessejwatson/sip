import SwiftUI

/// The last seven days, oldest first, one dot each.
struct WeekStrip: View {
    @Environment(Store.self) private var store
    @State private var selected: Date?

    private var days: [Date] {
        (0..<7).reversed().compactMap { store.calendar.date(byAdding: .day, value: -$0, to: store.today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let isToday = day == store.today
                    VStack(spacing: 4) {
                        Text(Weekday(of: day, calendar: store.calendar).initial)
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? .primary : .secondary)
                        DayDot(status: store.status(on: day), fraction: fraction(day))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { selected = day } else if selected == day { selected = nil }
                    }
                    .onTapGesture { selected = (selected == day) ? nil : day }
                    .help(summary(day))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary(day))
                }
            }
            Text(selected.map(summary) ?? "Last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func fraction(_ day: Date) -> Double {
        let goal = store.goal(on: day)
        return goal > 0 ? Double(store.total(on: day)) / Double(goal) : 0
    }

    private func summary(_ day: Date) -> String {
        let label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let total = store.total(on: day)
        if store.isExcluded(day) { return "\(label): on leave" + (total > 0 ? " (\(Volume.litres(total)) L)" : "") }
        if !store.isWorkDay(day) { return "\(label): not a work day" + (total > 0 ? " (\(Volume.litres(total)) L)" : "") }
        return "\(label): \(Volume.litres(total)) / \(Volume.litres(store.goal(on: day))) L"
    }
}

private struct DayDot: View {
    let status: DayStatus
    let fraction: Double
    private let size: CGFloat = 14

    var body: some View {
        ZStack {
            switch status {
            case .met:
                Circle().fill(Color.accentColor)
            case .partial:
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                Circle().fill(Color.accentColor)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size * max(0.2, min(fraction, 0.9)))
                    }
            case .none:
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            case .off:
                Capsule().fill(.tertiary).frame(width: size * 0.7, height: 2)
            }
        }
        .frame(width: size, height: size)
    }
}
