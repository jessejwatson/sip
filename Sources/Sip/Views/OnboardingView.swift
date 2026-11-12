import SwiftUI

/// First-launch setup: work hours → bottle size → goal.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store

    @State private var step = 0
    @State private var draft = UserSettings()
    @State private var goalTouched = false
    @State private var launchAtLogin = true

    private static let presets = [250, 500, 600, 750, 1000]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(title).font(.title2.weight(.semibold))
                    Text("Step \(step + 1) of 3").font(.callout).foregroundStyle(.secondary)
                }
            }

            Group {
                switch step {
                case 0: hoursStep
                case 1: vesselStep
                default: goalStep
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button("Next") { advance() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdvance)
                } else {
                    Button("Start sipping") {
                        model.finishOnboarding(settings: draft, launchAtLogin: launchAtLogin)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            draft = store.settings
            if !draft.hasOnboarded { draft.goalML = draft.recommendedGoalML }
            step = 0
            goalTouched = false
        }
    }

    private var title: String {
        switch step {
        case 0: "When do you work?"
        case 1: "Your bottle or cup"
        default: "Your daily goal"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 0: draft.hasValidHours && !draft.workDays.isEmpty
        case 1: (draft.vessels.first?.amountML ?? 0) > 0
        default: true
        }
    }

    private func advance() {
        // Keep the goal in step with the hours until the user picks one themselves.
        if step == 0, !goalTouched { draft.goalML = draft.recommendedGoalML }
        step += 1
    }

    private var hoursStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sip only reminds you during work hours, and only when you're falling behind.")
                .foregroundStyle(.secondary)
            WorkHoursEditor(settings: $draft)
                .fixedSize()
        }
    }

    private var vesselStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What do you usually drink from at your desk?")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Size", value: firstVesselAmount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("ml")
            }
            HStack {
                ForEach(Self.presets, id: \.self) { amount in
                    Button(Volume.ml(amount)) { firstVesselAmount.wrappedValue = amount }
                        .buttonStyle(.bordered)
                        .tint(firstVesselAmount.wrappedValue == amount ? .accentColor : nil)
                }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalEditor(settings: Binding(
                get: { draft },
                set: { draft = $0; goalTouched = true }
            ))
            Toggle("Launch Sip at login", isOn: $launchAtLogin)
            Text("Next, macOS will ask whether Sip can send notifications. Allow them to get reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var firstVesselAmount: Binding<Int> {
        Binding(
            get: { draft.vessels.first?.amountML ?? 0 },
            set: { amount in
                if draft.vessels.isEmpty {
                    draft.vessels = [Vessel(name: "Bottle", amountML: amount)]
                } else {
                    draft.vessels[0].amountML = amount
                }
            }
        )
    }
}
