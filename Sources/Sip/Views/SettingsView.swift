import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmingReset = false
    @State private var exportError: String?

    private let calendar = Calendar.current

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                DayChips(workDays: $store.settings.workDays)
                    .frame(maxWidth: .infinity)
                DatePicker("Start", selection: time(\.startTime), displayedComponents: .hourAndMinute)
                DatePicker("Finish", selection: time(\.endTime), displayedComponents: .hourAndMinute)
            } header: {
                Text("Work days and hours")
            } footer: {
                if store.settings.hasValidHours {
                    FooterText("\(hours(store.settings.workMinutes)) a day. Reminders only happen during these hours.")
                } else {
                    Label("Finish time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                LabeledContent("Daily goal") {
                    HStack(spacing: 8) {
                        Text("\(Volume.litres(store.settings.goalML)) L")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(store.settings.goalML)))
                            .animation(.snappy, value: store.settings.goalML)
                        Stepper("Daily goal", value: $store.settings.goalML, in: 250...5000, step: 50)
                            .labelsHidden()
                    }
                }
                Slider(
                    value: Binding(get: { Double(store.settings.goalML) },
                                   set: { store.settings.goalML = Int($0 / 50) * 50 }),
                    in: 250...4000
                ) {
                    Text("Adjust")
                }
                LabeledContent("Recommended for your hours") {
                    Button("Use \(Volume.litres(store.settings.recommendedGoalML)) L") {
                        store.settings.goalML = store.settings.recommendedGoalML
                    }
                    .disabled(store.settings.goalML == store.settings.recommendedGoalML)
                }
            } header: {
                Text("Goal")
            } footer: {
                FooterText(GoalEditor.guidance)
            }

            Section {
                ForEach($store.settings.vessels) { $vessel in
                    VesselRow(vessel: $vessel, canRemove: store.settings.vessels.count > 1) {
                        store.settings.vessels.removeAll { $0.id == vessel.id }
                    }
                }
                Button("Add a bottle or cup", systemImage: "plus") {
                    store.settings.vessels.append(Vessel(name: "Cup", amountML: 250))
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Bottles and cups")
            } footer: {
                FooterText("The first one is used by the “Log” button on reminders.")
            }

            Section {
                Picker("Minimum time between reminders", selection: $store.settings.reminderIntervalMinutes) {
                    ForEach([20, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
            } header: {
                Text("Reminders")
            } footer: {
                FooterText("You're only reminded when you fall behind pace.")
            }

            Section {
                LabeledContent("Drink history") {
                    Button("Export CSV…", action: exportCSV)
                }
                LabeledContent("Start over") {
                    Button("Reset all data…", role: .destructive) { confirmingReset = true }
                }
            } header: {
                Text("Data")
            } footer: {
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
        .tint(.water)
        .frame(width: 480, height: 680)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .confirmationDialog("Reset all data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetAllData() }
        } message: {
            Text("This deletes your drink history and settings. It can't be undone.")
        }
    }

    private func time(_ keyPath: WritableKeyPath<UserSettings, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { store.settings[keyPath: keyPath].date(on: Date(), calendar: calendar) },
            set: { store.settings[keyPath: keyPath] = TimeOfDay($0, calendar: calendar) }
        )
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Sip history \(store.key(for: store.today)).csv"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.csv().write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
        } catch {
            exportError = "Couldn't export: \(error.localizedDescription)"
        }
    }
}

/// "8 h", "7.5 h".
func hours(_ minutes: Int) -> String {
    "\((Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...1)))) h"
}

private struct FooterText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VesselRow: View {
    @Binding var vessel: Vessel
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: VesselSymbol.name(for: vessel.amountML))
                .foregroundStyle(.tint)
                .frame(width: 20)
            TextField("Name", text: $vessel.name, prompt: Text("Name"))
                .labelsHidden()
            TextField("Amount", value: $vessel.amountML, format: .number, prompt: Text("ml"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text("ml")
                .foregroundStyle(.secondary)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(canRemove ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .help(canRemove ? "Remove" : "You need at least one bottle or cup")
        }
    }
}

// MARK: - Shared editors

struct DayChips: View {
    @Binding var workDays: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.displayOrder, id: \.self) { day in
                DayChip(day: day, isOn: Binding(
                    get: { workDays.contains(day) },
                    set: { on in
                        if on { workDays.insert(day) } else { workDays.remove(day) }
                    }
                ))
            }
        }
    }
}

private struct DayChip: View {
    let day: Weekday
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(day.shortName)
                .font(.callout.weight(.medium))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Color.water.gradient) : AnyShapeStyle(.quaternary))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
        .accessibilityLabel(day.shortName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Day chips plus start and finish times, laid out for onboarding's card.
struct WorkHoursEditor: View {
    @Binding var settings: UserSettings
    let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DayChips(workDays: $settings.workDays)
            HStack(spacing: 8) {
                DatePicker("From", selection: timeBinding(\.startTime), displayedComponents: .hourAndMinute)
                    .fixedSize()
                DatePicker("to", selection: timeBinding(\.endTime), displayedComponents: .hourAndMinute)
                    .fixedSize()
                Spacer()
                if settings.hasValidHours {
                    Text("\(hours(settings.workMinutes)) a day")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if !settings.hasValidHours {
                Label("Finish time must be after start time.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<UserSettings, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { settings[keyPath: keyPath].date(on: Date(), calendar: calendar) },
            set: { settings[keyPath: keyPath] = TimeOfDay($0, calendar: calendar) }
        )
    }
}

/// Goal amount, slider and recommendation, laid out for onboarding's card.
struct GoalEditor: View {
    @Binding var settings: UserSettings

    static let guidance = "Based on Australian guidelines of about 2.1–2.6 L of drinks a day. Tea and coffee count. Adjust to suit you, or follow your doctor's advice."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Volume.litres(settings.goalML)) L")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(settings.goalML)))
                    .animation(.snappy, value: settings.goalML)
                if let vessel = settings.vessels.first, vessel.amountML > 0 {
                    Text("≈ \(Self.vesselCount(goal: settings.goalML, vessel: vessel))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper("Goal", value: $settings.goalML, in: 250...5000, step: 50)
                    .labelsHidden()
            }
            Slider(
                value: Binding(get: { Double(settings.goalML) }, set: { settings.goalML = Int($0 / 50) * 50 }),
                in: 250...4000
            )
            HStack {
                Text("Recommended for your hours: \(Volume.litres(settings.recommendedGoalML)) L")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use recommended") { settings.goalML = settings.recommendedGoalML }
                    .disabled(settings.goalML == settings.recommendedGoalML)
            }
            Text(Self.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "2.5 bottles", "1 bottle".
    static func vesselCount(goal: Int, vessel: Vessel) -> String {
        let count = (Double(goal) / Double(vessel.amountML) * 10).rounded() / 10
        let name = vessel.name.lowercased()
        let formatted = count.formatted(.number.precision(.fractionLength(0...1)))
        return count == 1 ? "1 \(name)" : "\(formatted) \(name)s"
    }
}
