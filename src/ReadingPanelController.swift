import AppKit

final class AskPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { orderOut(nil) }
    }
}

/// Controls only visibility. Hiding never mutates the selection, draft or request.
/// A nonactivating panel can coexist with a frontmost Books, so app-deactivation
/// notifications alone cannot implement outside-click dismissal.
@MainActor
final class ReadingPanelController: NSObject, NSWindowDelegate {
    let panel: AskPanel
    private let now: () -> TimeInterval
    private let record: ([String: Any]) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private(set) var presentationID = UUID()
    private(set) var deadline: TimeInterval?
    private(set) var automaticDismissal: Bool
    private var presentedAt: TimeInterval = 0
    static let delay: TimeInterval = 15

    init(panel: AskPanel, automaticDismissal: Bool,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         record: @escaping ([String: Any]) -> Void) {
        self.panel = panel
        self.automaticDismissal = automaticDismissal
        self.now = now
        self.record = record
        super.init()
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.dismiss(reason: "escape") }
    }

    func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated { self?.outsideClick(timestamp: event.timestamp, source: "global_mouse") }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union([.keyDown, .scrollWheel])) { [weak self] event in
            let deliver = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.handleLocalEvent(event) != nil
            }
            return deliver ? event : nil
        }
    }

    func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        cancelCountdown(reason: "shutdown")
    }

    /// Called only after an actual presentation, never by a stream update.
    func didPresent(forSelection: Bool) {
        cancelCountdown(reason: "new_presentation")
        presentationID = UUID()
        presentedAt = now()
        if forSelection && automaticDismissal { armCountdown() }
    }

    func setAutomaticDismissal(_ enabled: Bool) {
        automaticDismissal = enabled
        cancelCountdown(reason: "setting_changed")
        if enabled && panel.isVisible && !panel.isMiniaturized { armCountdown() }
    }

    func userInteracted() {
        // Reading/typing intentionally keeps this presentation open. The next
        // selection receives a fresh countdown; the saved checkbox stays on.
        cancelCountdown(reason: "panel_interaction")
    }

    func outsideClick(timestamp: TimeInterval, source: String) {
        guard timestamp >= presentedAt else { return }
        dismiss(reason: "outside_click", extra: ["source": source, "inputTimestamp": timestamp,
            "foregroundApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"])
    }

    @discardableResult
    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.timestamp >= presentedAt else { return event }
        let inside = isRelatedWindow(event.window)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if inside { userInteracted() }
            else if event.window != nil {
                outsideClick(timestamp: event.timestamp, source: "local_mouse")
            }
        case .keyDown:
            if inside {
                if event.keyCode == 53 { dismiss(reason: "escape"); return nil }
                userInteracted()
            }
        case .scrollWheel:
            if inside { userInteracted() }
        default: break
        }
        // The same click continues to the destination control/window.
        return event
    }

    func dismiss(reason: String, extra: [String: Any] = [:]) {
        cancelCountdown(reason: reason)
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        var fields = extra
        fields["event"] = "window_dismissed"
        fields["reason"] = reason
        fields["presentationID"] = presentationID.uuidString
        fields["visibleAfter"] = panel.isVisible
        fields["sincePresentationSeconds"] = now() - presentedAt
        record(fields)
    }

    private func isRelatedWindow(_ window: NSWindow?) -> Bool {
        var current = window
        while let candidate = current {
            if candidate === panel { return true }
            current = candidate.parent ?? candidate.sheetParent
        }
        return false
    }

    private func armCountdown() {
        deadline = now() + Self.delay
        let id = presentationID
        let next = Timer(timeInterval: Self.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.countdownFired(for: id) }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
        record(["event": "window_auto_hide_scheduled", "presentationID": id.uuidString,
                "delaySeconds": Self.delay, "deadlineUptime": deadline!])
    }

    /// The identity and deadline prevent an old timer from hiding a newer word,
    /// or a queued timer callback from hiding after the option was turned off.
    func countdownFired(for id: UUID) {
        guard automaticDismissal, id == presentationID, let deadline,
              now() >= deadline, panel.isVisible, !panel.isMiniaturized else { return }
        dismiss(reason: "timeout")
    }

    private func cancelCountdown(reason: String) {
        timer?.invalidate()
        timer = nil
        if deadline != nil {
            record(["event": "window_auto_hide_cancelled", "presentationID": presentationID.uuidString,
                    "reason": reason])
        }
        deadline = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(reason: "close_button")
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        cancelCountdown(reason: "minimized")
    }

    func windowDidResignKey(_ notification: Notification) {
        let id = presentationID
        // AppKit updates the next key window after posting resign-key. Preserve
        // attached sheets/popovers, and do not let an old notification hide a
        // newly presented selection in the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, id == self.presentationID, !self.panel.isKeyWindow,
                  !self.isRelatedWindow(NSApp.keyWindow) else { return }
            self.dismiss(reason: "focus_left_panel")
        }
    }
}
