import SwiftUI

/// The last seven days, oldest first, one dot each.
struct WeekStrip: View {
    @Environment(Store.self) private var store
    @State private var selected: Date?

    private var days: [Date] {
        (0..<7).reversed().compactMap { store.calendar.date(byAdding: .day, value: -$0, to: store.today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let isToday = day == store.today
                    VStack(spacing: 6) {
                        Text(Weekday(of: day, calendar: store.calendar).initial)
                            .font(.caption2.weight(isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        DayDot(status: store.status(on: day), fraction: fraction(day))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(selected == day ? 1 : isToday ? 0.6 : 0))
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { selected = day } else if selected == day { selected = nil }
                    }
                    .onTapGesture { selected = (selected == day) ? nil : day }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary(day))
                }
            }
            Text(selected.map(summary) ?? "Point at a day to see its total")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(nil, value: selected)
        }
    }

    private func fraction(_ day: Date) -> Double {
        let goal = store.goal(on: day)
        return goal > 0 ? Double(store.total(on: day)) / Double(goal) : 0
    }

    private func summary(_ day: Date) -> String {
        let label = day == store.today ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        let total = store.total(on: day)
        let extra = total > 0 ? " · \(Volume.litres(total)) L" : ""
        if store.isExcluded(day) { return "\(label): on leave\(extra)" }
        if !store.isWorkDay(day) { return "\(label): not a work day\(extra)" }
        return "\(label): \(Volume.litres(total)) of \(Volume.litres(store.goal(on: day))) L"
    }
}

private struct DayDot: View {
    let status: DayStatus
    let fraction: Double
    private let size: CGFloat = 18

    var body: some View {
        ZStack {
            switch status {
            case .met:
                Circle().fill(Color.water.gradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            case .partial:
                Circle().fill(.quaternary)
                Circle()
                    .trim(from: 0, to: max(0.08, min(fraction, 0.95)))
                    .stroke(Color.water, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            case .none:
                Circle().strokeBorder(.tertiary, lineWidth: 1.5)
            case .off:
                Capsule().fill(.tertiary).frame(width: size * 0.6, height: 2.5)
            }
        }
        .frame(width: size, height: size)
    }
}
