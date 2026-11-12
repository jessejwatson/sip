import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmingReset = false
    @State private var exportError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Work days and hours") {
                WorkHoursEditor(settings: $store.settings)
            }

            Section("Daily goal") {
                GoalEditor(settings: $store.settings)
            }

            Section("Bottles and cups") {
                VesselListEditor(vessels: $store.settings.vessels)
            }

            Section("Reminders") {
                Picker("Minimum gap between reminders", selection: $store.settings.reminderIntervalMinutes) {
                    ForEach([20, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                }
                Text("You'll only be reminded when you fall behind pace during work hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }

            Section("Data") {
                HStack {
                    Button("Export CSV…", action: exportCSV)
                    Spacer()
                    Button("Reset all data…", role: .destructive) { confirmingReset = true }
                }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .confirmationDialog("Reset all data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetAllData() }
        } message: {
            Text("This deletes your drink history and settings. It can't be undone.")
        }
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

// MARK: - Shared editors (used by onboarding too)

struct WorkHoursEditor: View {
    @Binding var settings: UserSettings
    let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Weekday.displayOrder, id: \.self) { day in
                    Toggle(day.shortName, isOn: Binding(
                        get: { settings.workDays.contains(day) },
                        set: { on in
                            if on { settings.workDays.insert(day) } else { settings.workDays.remove(day) }
                        }
                    ))
                    .toggleStyle(.button)
                }
            }
            DatePicker("Start", selection: timeBinding(\.startTime), displayedComponents: .hourAndMinute)
            DatePicker("Finish", selection: timeBinding(\.endTime), displayedComponents: .hourAndMinute)
            if !settings.hasValidHours {
                Label("Finish time must be after start time.", systemImage: "exclamationmark.triangle")
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

struct GoalEditor: View {
    @Binding var settings: UserSettings

    static let guidance = "Based on Australian guidelines of about 2.1–2.6 L of drinks a day. Tea and coffee count. Adjust to suit you, or follow your doctor's advice."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Volume.litres(settings.goalML)) L")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
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

struct VesselListEditor: View {
    @Binding var vessels: [Vessel]

    var body: some View {
        ForEach($vessels) { $vessel in
            HStack {
                TextField("Name", text: $vessel.name)
                    .labelsHidden()
                TextField("Amount", value: $vessel.amountML, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("ml").foregroundStyle(.secondary)
                Button {
                    vessels.removeAll { $0.id == vessel.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(vessels.count <= 1)
                .help(vessels.count <= 1 ? "You need at least one bottle or cup" : "Remove")
            }
        }
        Button("Add bottle or cup", systemImage: "plus") {
            vessels.append(Vessel(name: "Cup", amountML: 250))
        }
        .buttonStyle(.borderless)
        Text("The first one is used for the “Log” button on reminders.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
