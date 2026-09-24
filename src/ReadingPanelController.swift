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
    private(set) var presentationID = UUID()
    private var presentedAt: TimeInterval = 0
    var isPinned = false
    var automaticDismissalSuspended = false
    private var keepsOpen: Bool { isPinned || automaticDismissalSuspended || panel.attachedSheet != nil }

    init(panel: AskPanel,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         record: @escaping ([String: Any]) -> Void) {
        self.panel = panel
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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union([.keyDown])) { [weak self] event in
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
    }

    /// Called only after an actual presentation, never by a stream update.
    func didPresent() {
        presentationID = UUID()
        presentedAt = now()
    }

    func outsideClick(timestamp: TimeInterval, source: String) {
        guard timestamp >= presentedAt, !keepsOpen else { return }
        dismiss(reason: "outside_click", extra: ["source": source, "inputTimestamp": timestamp,
            "foregroundApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"])
    }

    @discardableResult
    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, event.timestamp >= presentedAt else { return event }
        let inside = isRelatedWindow(event.window)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !inside && event.window != nil {
                outsideClick(timestamp: event.timestamp, source: "local_mouse")
            }
        case .keyDown:
            if inside {
                if event.keyCode == 53 && event.window === panel && panel.attachedSheet == nil { dismiss(reason: "escape"); return nil }
            }
        default: break
        }
        // The same click continues to the destination control/window.
        return event
    }

    func dismiss(reason: String, extra: [String: Any] = [:]) {
        guard panel.isVisible else { return }
        if !panel.frameAutosaveName.isEmpty { panel.saveFrame(usingName: panel.frameAutosaveName) }
        panel.orderOut(nil)
        var fields = extra
        fields["event"] = "window_dismissed"
        fields["reason"] = reason
        fields["presentationID"] = presentationID.uuidString
        fields["visibleAfter"] = panel.isVisible
        fields["sincePresentationSeconds"] = now() - presentedAt
        record(fields)
    }

    /// Preserve the chosen position while keeping a restored window reachable
    /// after a monitor is disconnected or its usable area changes.
    static func visibleOrigin(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(x: min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
                y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height)))
    }

    private func isRelatedWindow(_ window: NSWindow?) -> Bool {
        var current = window
        while let candidate = current {
            if candidate === panel { return true }
            current = candidate.parent ?? candidate.sheetParent
        }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(reason: "close_button")
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        let id = presentationID
        // AppKit updates the next key window after posting resign-key. Preserve
        // attached sheets/popovers, and do not let an old notification hide a
        // newly presented selection in the next run-loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.keepsOpen, id == self.presentationID, !self.panel.isKeyWindow,
                  !self.isRelatedWindow(NSApp.keyWindow) else { return }
            self.dismiss(reason: "focus_left_panel")
        }
    }
}
