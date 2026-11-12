import SwiftUI

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store
    @Environment(\.openSettings) private var openSettings

    @State private var showingCustom = false
    @State private var customAmount: Int?
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.settings.hasOnboarded {
                Button("Finish setting up Sip…") { model.showOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

            progress
            quickAdd
            Divider()
            WeekStrip()
            Toggle("Mark today as leave", isOn: Binding(
                get: { store.isTodayExcluded },
                set: { store.setExcluded($0, on: store.today) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { store.refreshDay() }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Volume.litres(store.todayTotal)) / \(Volume.litres(store.todayGoal)) L")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text("\(Int((store.todayFraction * 100).rounded()))%")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(store.todayFraction, 1))
                .tint(store.todayFraction >= 1 ? .green : .accentColor)
            if store.isTodayOff {
                Text(store.isTodayExcluded ? "On leave today: no reminders." : "Not a work day: no reminders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.settings.vessels) { vessel in
                Button {
                    model.log(vessel.amountML)
                } label: {
                    HStack {
                        Label(vessel.name, systemImage: "plus.circle.fill")
                        Spacer()
                        Text(Volume.ml(vessel.amountML)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            if showingCustom {
                HStack {
                    TextField("Amount", value: $customAmount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .focused($customFocused)
                        .onSubmit(addCustom)
                    Text("ml").foregroundStyle(.secondary)
                    Button("Add", action: addCustom)
                        .keyboardShortcut(.defaultAction)
                        .disabled((customAmount ?? 0) <= 0)
                    Button("Cancel") { showingCustom = false }
                }
            }

            HStack {
                if !showingCustom {
                    Button("Custom…") {
                        customAmount = nil
                        showingCustom = true
                        customFocused = true
                    }
                }
                Spacer()
                if !store.todayEntries.isEmpty {
                    Button("Undo last", systemImage: "arrow.uturn.backward") { store.undoLast() }
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit Sip") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func addCustom() {
        guard let amount = customAmount, amount > 0 else { return }
        model.log(min(amount, 5000))
        showingCustom = false
    }
}
