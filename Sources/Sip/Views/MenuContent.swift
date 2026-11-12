import SwiftUI

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if !store.settings.hasOnboarded {
                SetupBanner { model.showOnboarding() }
            }
            TodayHeader()
            QuickAddGrid()
            WeekCard()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .tint(.water)
        .background(PopoverChrome())
        .clipShape(PopoverChrome.shape)
        .overlay(PopoverChrome.shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .onAppear { store.refreshDay() }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                model.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",")

            Spacer()

            if let last = store.todayEntries.max(by: { $0.timestamp < $1.timestamp }) {
                Button {
                    withAnimation(.snappy) { store.undoLast() }
                } label: {
                    Label("Undo \(Volume.ml(last.amountML))", systemImage: "arrow.uturn.backward")
                }
                .help("Remove the \(Volume.ml(last.amountML)) logged at \(last.timestamp.formatted(date: .omitted, time: .shortened))")
                .transition(.opacity)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(FooterButtonStyle())
        .padding(.top, 2)
    }
}

// MARK: - Header

private struct TodayHeader: View {
    @Environment(Store.self) private var store

    var body: some View {
        // Re-evaluate the pace message every minute while the popover is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let _ = context.date // re-render each minute
            let status = PaceStatus(store: store, now: store.now())
            HStack(spacing: 16) {
                ProgressRing(fraction: store.todayFraction, tint: status.tint)
                    .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.today.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Volume.litres(store.todayTotal)) L")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText(value: Double(store.todayTotal)))
                        Text("of \(Volume.litres(store.todayGoal)) L")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                    Label(status.message, systemImage: status.symbol)
                        .font(.callout)
                        .foregroundStyle(status.tint)
                        .labelStyle(StatusLabelStyle())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .animation(.snappy, value: store.todayTotal)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressRing: View {
    let fraction: Double
    let tint: Color
    private let lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(fraction > 0 ? 1 : 0)
            VStack(spacing: 0) {
                Image(systemName: fraction >= 1 ? "drop.fill" : "drop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: fraction))
            }
        }
        .animation(.spring(duration: 0.6), value: fraction)
    }
}

/// One-line summary of how today is going.
private struct PaceStatus {
    let message: String
    let symbol: String
    let tint: Color

    @MainActor
    init(store: Store, now: Date) {
        let settings = store.settings
        let total = store.todayTotal
        let goal = store.todayGoal
        let nowMinutes = Pacing.minutesSinceMidnight(now, calendar: store.calendar)

        if total >= goal, goal > 0 {
            (message, symbol, tint) = ("Goal reached. Nice work!", "checkmark.circle.fill", .green)
        } else if store.isTodayExcluded {
            (message, symbol, tint) = ("On leave: no reminders", "moon.zzz.fill", .secondary)
        } else if !store.isWorkDay(store.today) {
            (message, symbol, tint) = ("Day off: no reminders", "moon.zzz.fill", .secondary)
        } else if nowMinutes < Double(settings.startTime.minutesSinceMidnight) {
            let start = settings.startTime.date(on: now, calendar: store.calendar)
            (message, symbol, tint) = ("Your day starts at \(start.formatted(date: .omitted, time: .shortened))",
                                       "sunrise.fill", .secondary)
        } else {
            let expected = Pacing.expected(goalML: goal, settings: settings, now: now, calendar: store.calendar)
            if Pacing.isBehind(expectedML: expected, actualML: total) {
                (message, symbol, tint) = ("\(Volume.ml(Self.round50(expected - total))) behind pace",
                                           "exclamationmark.circle.fill", .orange)
            } else {
                (message, symbol, tint) = ("On track · \(Volume.ml(goal - total)) to go", "hand.thumbsup.fill", .water)
            }
        }
    }

    private static func round50(_ ml: Int) -> Int { max(50, Int((Double(ml) / 50).rounded()) * 50) }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.caption)
            configuration.title
        }
    }
}

private struct SetupBanner: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "sparkles")
                Text("Finish setting up Sip")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .foregroundStyle(.white)
            .background(Color.water.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick add

private struct QuickAddGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(Store.self) private var store

    @State private var showingCustom = false
    @State private var customAmount: Int?
    @FocusState private var customFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.settings.vessels) { vessel in
                    Button {
                        model.log(vessel.amountML)
                    } label: {
                        TileLabel(symbol: VesselSymbol.name(for: vessel.amountML),
                                  title: vessel.name, detail: Volume.ml(vessel.amountML))
                    }
                    .help("Log \(Volume.ml(vessel.amountML))")
                }
                Button {
                    withAnimation(.snappy) { showingCustom.toggle() }
                    if showingCustom {
                        customAmount = nil
                        customFocused = true
                    }
                } label: {
                    TileLabel(symbol: "plus", title: "Custom", detail: "Any amount", isSecondary: true)
                }
            }
            .buttonStyle(TileButtonStyle())

            if showingCustom {
                HStack(spacing: 8) {
                    TextField("Amount", value: $customAmount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .focused($customFocused)
                        .onSubmit(addCustom)
                        .onExitCommand { withAnimation(.snappy) { showingCustom = false } }
                    Text("ml").foregroundStyle(.secondary)
                    Button("Add", action: addCustom)
                        .buttonStyle(.borderedProminent)
                        .disabled((customAmount ?? 0) <= 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func addCustom() {
        guard let amount = customAmount, amount > 0 else { return }
        model.log(min(amount, 5000))
        withAnimation(.snappy) { showingCustom = false }
    }
}

private struct TileLabel: View {
    let symbol: String
    let title: String
    let detail: String
    var isSecondary = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(height: 24)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
    }
}

enum VesselSymbol {
    static func name(for amountML: Int) -> String {
        let candidate = amountML <= 350 ? "mug.fill" : "waterbottle.fill"
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) == nil ? "drop.fill" : candidate
    }
}

// MARK: - Week

private struct WeekCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WeekStrip()
            Divider()
            Toggle(isOn: Binding(
                get: { store.isTodayExcluded },
                set: { excluded in withAnimation(.snappy) { store.setExcluded(excluded, on: store.today) } }
            )) {
                Label("On leave today", systemImage: "beach.umbrella")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "3 of 4 work days" — met days among the last seven, not counting today unless it's done.
    private var summary: String {
        let days = (0..<7).compactMap { store.calendar.date(byAdding: .day, value: -$0, to: store.today) }
        let statuses = days.map { ($0, store.status(on: $0)) }
        let counted = statuses.filter { day, status in
            status != .off && (day != store.today || status == .met)
        }
        guard !counted.isEmpty else { return "" }
        let met = counted.filter { $0.1 == .met }.count
        return "Goal met \(met) of \(counted.count) work days"
    }
}

// MARK: - Styles

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.5)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.tint.opacity(hovering ? 0.5 : 0), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterBody(configuration: configuration)
    }

    private struct FooterBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(hovering ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.quaternary.opacity(hovering || configuration.isPressed ? 1 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Window chrome

/// The panel's translucent background. Behind-window blur is composited by the window server,
/// which ignores layer masks, so the rounded shape comes from `maskImage`; the borderless panel's
/// shadow then follows that shape.
private struct PopoverChrome: NSViewRepresentable {
    static let cornerRadius: CGFloat = 14
    static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.maskImage
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded rect, the documented way to shape an NSVisualEffectView.
    private static let maskImage: NSImage = {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }()
}
