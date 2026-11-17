import AppKit
import Observation
import SwiftUI

/// The menu bar icon and its drop-down panel.
///
/// MenuBarExtra's `.window` style draws its own square background and border that can't be fully
/// replaced, so Sip owns the panel: borderless, transparent, with one rounded background drawn by
/// `MenuContent` and a shadow that follows it.
@MainActor
final class StatusItemController: NSObject {
    private static let gap: CGFloat = 5
    private static let screenMargin: CGFloat = 8

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: StatusPanel
    private var monitors: [Any] = []
    private var resizeObserver: NSObjectProtocol?
    /// Pace changes with the clock as well as the store, so the icon is also redrawn every minute.
    private var iconTimer: Timer?
    /// Top-centre point of the panel, just below the status item.
    private var anchor = NSPoint.zero

    var isShown: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        let host = NSHostingController(rootView: MenuContent().environment(model).environment(model.store))
        host.sizingOptions = .preferredContentSize
        panel = StatusPanel(contentViewController: host)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // Content changes (e.g. the custom amount field) resize the panel from its bottom-left corner;
        // keep it hanging from the menu bar instead.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        updateIcon()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyIcon() }
        }
    }

    @objc private func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        model.store.refreshDay()
        Task { await model.notifications.refreshPermission() }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchor = NSPoint(x: buttonFrame.midX, y: buttonFrame.minY - Self.gap)
        reposition()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        installMonitors()
    }

    func close() {
        guard isShown else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        removeMonitors()
    }

    private func reposition() {
        let size = panel.frame.size
        guard size.width > 0 else { return }
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        var x = anchor.x - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: (anchor.y - size.height).rounded()))
        panel.invalidateShadow()
    }

    // MARK: Dismissal

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps (and on the desktop) close the panel, like a menu. The menu bar can report
        // a click on Sip's own icon here too; leave that one to `toggle`, or the panel closes and reopens.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isOverIcon(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let isEscape = event.keyCode == 53
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard isEscape, let self, self.panel.isKeyWindow else { return false }
                self.close()
                return true
            }
            return handled ? nil : event
        }) {
            monitors.append(local)
        }
    }

    private func isOverIcon(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    // MARK: Icon

    private func updateIcon() {
        withObservationTracking {
            applyIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    private func applyIcon() {
        let store = model.store
        let isBehind = MenuBarIcon.isBehind(store)
        statusItem.button?.image = MenuBarIcon.image(for: store, isBehind: isBehind)
        statusItem.button?.setAccessibilityLabel(MenuBarIcon.accessibilityLabel(for: store, isBehind: isBehind))
    }
}

/// A borderless panel that can take keyboard focus (for the custom amount field) without
/// activating the app or stealing focus from the window underneath.
final class StatusPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum MenuBarIcon {
    @MainActor
    static func isBehind(_ store: Store) -> Bool {
        if case .behind = store.pace(at: store.now()) { return true }
        return false
    }

    @MainActor
    static func image(for store: Store, isBehind: Bool) -> NSImage {
        let base = image(symbol: symbolName(for: store), dimmed: store.isTodayOff)
        return isBehind ? badged(base) : base
    }

    @MainActor
    static func accessibilityLabel(for store: Store, isBehind: Bool) -> String {
        "Sip, \(Int((store.todayFraction * 100).rounded()))% of today's goal\(isBehind ? ", behind pace" : "")"
    }

    @MainActor
    private static func symbolName(for store: Store) -> String {
        if store.isTodayOff { return "drop" }
        let fraction = store.todayFraction
        if fraction >= 1 { return "drop.fill" }
        if fraction >= 0.34 { return "drop.halffull" }
        return "drop"
    }

    /// Dimming is baked into the template image's alpha so it still adapts to the menu bar's appearance.
    private static func image(symbol: String, dimmed: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "drop", accessibilityDescription: nil)
            ?? NSImage()
        guard dimmed else {
            base.isTemplate = true
            return base
        }
        let dimmedImage = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        dimmedImage.isTemplate = true
        return dimmedImage
    }

    /// Adds a small "!" badge at the bottom right, with a gap cut around it so it reads against the drop.
    private static func badged(_ base: NSImage) -> NSImage {
        guard let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 6.5, weight: .heavy)) else { return base }
        let size = NSSize(width: base.size.width + badge.size.width * 0.6, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(origin: .zero, size: base.size))
            let badgeRect = NSRect(x: rect.maxX - badge.size.width, y: rect.minY,
                                   width: badge.size.width, height: badge.size.height)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1.25, dy: -1.25)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
