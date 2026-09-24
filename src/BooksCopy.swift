import AppKit
import ApplicationServices

/// Issues exactly one Books copy action for a verified selection gesture.
/// Preferred path is the Books menu bar Copy item (no injected key events);
/// a ⌘C event targeted at the Books PID is used only when no usable menu
/// item exists. Both paths share the single system pasteboard.
enum BooksCopy {
    // Only our own targeted copy fallback is exempt from dismissal monitoring.
    // A physical user key, including Command-C, still invalidates stale intent.
    static let copyEventTag: Int64 = 0x424F4F4B41534B
    static func isOwnCopyEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 8 && event.modifierFlags.contains(.command)
            && event.cgEvent?.getIntegerValueField(.eventSourceUserData) == copyEventTag
    }
    enum Method: String {
        case none, menu, shortcut
    }

    /// A copy may only follow a real selection gesture: a drag (any distance) or a
    /// double/triple click. Plain clicks, scrolls, poll ticks and selections left
    /// over from app launch never issue a copy.
    static func isSelectionGesture(dragged: Bool, clickCount: Int, button: Int) -> Bool {
        button == 0 && (dragged || clickCount >= 2)
    }

    static func issue(to pid: pid_t, outcome: inout CaptureOutcome) -> Bool {
        if pressMenuCopy(pid: pid) {
            outcome.issueMethod = Method.menu.rawValue
            return true
        }
        if postShortcutCopy(pid: pid) {
            outcome.issueMethod = Method.shortcut.rawValue
            return true
        }
        outcome.issueMethod = Method.none.rawValue
        return false
    }

    /// Finds an enabled menu bar item with ⌘C (command key, no other modifiers)
    /// anywhere in the Books menu bar and presses it. Title-independent so both
    /// "Copy" and 「拷贝」 resolve through the key equivalent.
    static func pressMenuCopy(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let menuBar = value, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return false }
        let bar = menuBar as! AXUIElement
        guard let barItems = copyChildren(bar) else { return false }
        for barItem in barItems {
            guard let menuChildren = copyChildren(barItem), let menu = menuChildren.first else { continue }
            guard let items = copyChildren(menu) else { continue }
            for item in items {
                // AXMenuItemCmdChar case differs across apps/locales ("C" vs "c").
                guard let command = stringAttribute(item, "AXMenuItemCmdChar"),
                      command.caseInsensitiveCompare("c") == .orderedSame else { continue }
                // The SDK attribute includes "Cmd". An unreadable modifier mask
                // cannot establish that this is Copy rather than Copy Style.
                guard intAttribute(item, "AXMenuItemCmdModifiers") == 0 else { continue }
                if let enabled = boolAttribute(item, kAXEnabledAttribute), !enabled { continue }
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
        }
        return false
    }

    /// Targeted ⌘C. Events are posted to the Books PID only, never to whatever
    /// happens to be frontmost. Requires this process to be accessibility-trusted;
    /// without it the events may be dropped silently, which the capture timeout
    /// surfaces as a rejection rather than a wrong result.
    static func postShortcutCopy(pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: copyEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: copyEventTag)
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func intAttribute(_ element: AXUIElement, _ name: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
