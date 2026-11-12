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
    private static let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.bottom, 20)

            Group {
                switch step {
                case 0: hoursStep
                case 1: vesselStep
                default: goalStep
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 24)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation(.snappy) { step -= 1 } }
                        .controlSize(.large)
                }
                Spacer()
                if step < Self.stepCount - 1 {
                    Button("Continue") { advance() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdvance)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Start sipping") {
                        model.finishOnboarding(settings: draft, launchAtLogin: launchAtLogin)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .frame(width: 480)
        .tint(.water)
        .onAppear {
            draft = store.settings
            if !draft.hasOnboarded { draft.goalML = draft.recommendedGoalML }
            step = 0
            goalTouched = false
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.water.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 6) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(Color.water) : AnyShapeStyle(.quaternary))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            .padding(.top, 4)
            .animation(.snappy, value: step)
        }
    }

    private var icon: String {
        switch step {
        case 0: "calendar"
        case 1: VesselSymbol.name(for: draft.vessels.first?.amountML ?? 750)
        default: "target"
        }
    }

    private var title: String {
        switch step {
        case 0: "When do you work?"
        case 1: "What do you drink from?"
        default: "Set your daily goal"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: "Sip only reminds you during work hours, and only when you're falling behind."
        case 1: "The bottle or cup you usually keep at your desk. You can add more later."
        default: "How much to drink across your work day."
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
        withAnimation(.snappy) { step += 1 }
    }

    private var hoursStep: some View {
        WorkHoursEditor(settings: $draft)
    }

    private var vesselStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { amount in
                    let selected = firstVesselAmount.wrappedValue == amount
                    Button { firstVesselAmount.wrappedValue = amount } label: {
                        VStack(spacing: 6) {
                            Image(systemName: VesselSymbol.name(for: amount))
                                .font(.system(size: 18, weight: .medium))
                                .frame(height: 22)
                            Text(Volume.ml(amount))
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? AnyShapeStyle(Color.water.gradient) : AnyShapeStyle(.background))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.snappy(duration: 0.2), value: firstVesselAmount.wrappedValue)

            HStack {
                Text("Or enter a size")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Size", value: firstVesselAmount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("ml")
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalEditor(settings: Binding(
                get: { draft },
                set: { draft = $0; goalTouched = true }
            ))
            Divider()
            Toggle(isOn: $launchAtLogin) {
                Label("Launch Sip at login", systemImage: "power")
            }
            .toggleStyle(.switch)
            Text("Next, macOS will ask whether Sip can send notifications. Allow them to get reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
