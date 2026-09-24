import AppKit

/// AppKit component/integration coverage. The external Books gesture and the OS
/// global monitor are verified separately in the installed app, not faked here.
@main struct ReadingPanelTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = AskPanel(contentRect: NSRect(x: -20000, y: -20000, width: 500, height: 511),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var clock = 100.0
        var events = [[String: Any]]()
        let controller = ReadingPanelController(panel: panel,
            now: { clock }, record: { events.append($0) })
        func check(_ result: Bool, _ name: String) {
            if !result { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        // Offset Books windows must use their own middle, not the display's.
        // Both axes are in AppKit screen coordinates after the Quartz conversion.
        let display = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = NSRect(x: 0, y: 83, width: 1728, height: 1001)
        let book = NSRect(x: 40, y: 180, width: 1000, height: 800)
        let size = NSSize(width: 500, height: 539)
        let rightSelection = ReadingPanelPlacement(mousePoint: NSPoint(x: 800, y: 500), booksFrame: book,
            screenFrame: display, displayID: 1, eventTimestamp: 90)
        check(rightSelection.side == .left && rightSelection.referenceSource == "books_window"
              && rightSelection.origin(in: visible, panelSize: size) == NSPoint(x: 0, y: 545),
              "right side of an offset Books window opens top-left")
        let leftSelection = ReadingPanelPlacement(mousePoint: NSPoint(x: 200, y: 500), booksFrame: book,
            screenFrame: display, displayID: 1, eventTimestamp: 91)
        check(leftSelection.side == .right && leftSelection.origin(in: visible, panelSize: size) == NSPoint(x: 1228, y: 545),
              "left side of Books opens top-right with the existing size")
        let unavailableBounds = ReadingPanelPlacement(mousePoint: NSPoint(x: 1200, y: 500), booksFrame: book,
            screenFrame: display, displayID: 1, eventTimestamp: 92)
        check(unavailableBounds.referenceSource == "screen" && unavailableBounds.side == .left,
              "unrelated/non-containing window bounds use the selection display")
        let secondDisplay = NSRect(x: -1920, y: 100, width: 1920, height: 1080)
        let secondVisible = NSRect(x: -1920, y: 100, width: 1920, height: 1050)
        let secondPoint = ReadingPanelPlacement.fromQuartz(CGPoint(x: -1500, y: 200), primaryScreenTop: 1117)
        let external = ReadingPanelPlacement(mousePoint: secondPoint, booksFrame: nil,
            screenFrame: secondDisplay, displayID: 2, eventTimestamp: 93)
        check(secondPoint == NSPoint(x: -1500, y: 917) && external.side == .right
              && external.origin(in: secondVisible, panelSize: size) == NSPoint(x: -500, y: 611),
              "left/above external monitor keeps negative coordinates and correct vertical conversion")
        check(rightSelection.mousePoint.x == 800 && rightSelection.side == .left && rightSelection.eventTimestamp == 90,
              "a later selection's coordinates cannot alter the earlier immutable capture")
        func show() {
            panel.orderFront(nil)
            controller.didPresent()
            check(panel.isVisible, "offscreen fixture is ordered in")
        }
        show()
        show()
        controller.isPinned = true
        controller.outsideClick(timestamp: clock, source: "global_mouse")
        check(panel.isVisible, "Pin keeps the panel visible on outside clicks")
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        check(panel.isVisible, "Pin also survives the deferred focus-loss path")
        panel.cancelOperation(nil)
        check(!panel.isVisible, "Escape still hides a pinned panel")
        show()
        controller.isPinned = false
        controller.outsideClick(timestamp: clock, source: "global_mouse")
        check(!panel.isVisible, "Unpin restores outside-click dismissal")
        show()
        // Actual user failure: Books stays frontmost while a nonactivating panel
        // is visible. A Books click must hide the panel even without app change.
        if !CommandLine.arguments.contains("--old-no-outside-dismiss") {
            controller.outsideClick(timestamp: clock, source: "global_mouse")
        }
        check(!panel.isVisible, "clicking Books must actively hide the reading panel")
        check(events.contains { $0["event"] as? String == "window_dismissed" && $0["visibleAfter"] as? Bool == false },
              "dismissal logs the observed hidden state")

        show()
        let inside = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: clock, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        check(controller.handleLocalEvent(inside) === inside && panel.isVisible,
              "inside clicks reach the original control and keep the panel open")
        let otherWindow = NSWindow(contentRect: NSRect(x: -22000, y: -20000, width: 200, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let outside = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: clock, windowNumber: otherWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        check(controller.handleLocalEvent(outside) === outside && !panel.isVisible,
              "clicks to another app-owned window hide and are not consumed")
        show()
        panel.cancelOperation(nil)
        check(!panel.isVisible, "Escape hides the panel")
        show()
        check(!controller.windowShouldClose(panel) && !panel.isVisible,
              "red close button hides without releasing the reusable panel")

        show()
        clock += 30
        controller.outsideClick(timestamp: clock - 40, source: "queued_old_click")
        check(panel.isVisible, "queued mouse-down from before presentation cannot instantly hide it")
        controller.dismiss(reason: "test_complete")
        controller.stopMonitoring()

        // Exercise the actual application window layout at the user's minimum
        // size. All four controls must fit rather than silently clipping text.
        let legacy = UserDefaults.standard.object(forKey: "autoDismissAfter15Seconds")
        UserDefaults.standard.set(true, forKey: "autoDismissAfter15Seconds")
        defer { UserDefaults.standard.set(legacy, forKey: "autoDismissAfter15Seconds") }
        let owner = BookAsk()
        owner.recordSink = { _ in }
        owner.buildWindow()
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        let controls = [owner.automaticButton!, owner.smallerAnswerButton!, owner.largerAnswerButton!, owner.styleButton!, owner.promptDisclosure!]
        for button in controls {
            check(button.frame.width >= button.intrinsicContentSize.width - 0.5,
                  "top-row label must fit at 500-point width: \(button.title)")
            check(button.frame.minX >= 0 && button.frame.maxX <= 500,
                  "top-row button must stay inside the window: \(button.title)")
        }
        owner.question.stringValue = "an unsent question"
        owner.transcript.string = "existing answer"
        owner.selectedText = "current word"
        owner.messages = [["role": "assistant", "content": "existing answer"]]
        let generation = owner.activeGeneration
        owner.panelController.dismiss(reason: "component_test")
        check(owner.question.stringValue == "an unsent question" && owner.transcript.string == "existing answer"
              && owner.selectedText == "current word" && owner.messages.count == 1 && owner.activeGeneration == generation,
              "hiding preserves the draft, answer, selection, conversation and request generation")
        owner.currentPlacement = leftSelection
        owner.activeCaptureID = "latest-gesture"
        let stale = CaptureOutcome(captureID: "old-gesture", strategy: "component-test", acceptedText: "current word")
        owner.finishCopyCapture(stale, pid: 0, placement: rightSelection)
        check(owner.currentPlacement?.eventTimestamp == 91 && !owner.panel.isVisible,
              "late result from an older capture cannot move or reopen the panel")
        let failed = CaptureOutcome(captureID: "latest-gesture", strategy: "component-test")
        owner.finishCopyCapture(failed, pid: 0, placement: rightSelection)
        check(owner.currentPlacement?.eventTimestamp == 91 && !owner.panel.isVisible,
              "failed capture cannot replace the previous placement")
        owner.activeCaptureID = "repeat-gesture"
        let repeated = CaptureOutcome(captureID: "repeat-gesture", strategy: "component-test", acceptedText: "current word")
        owner.finishCopyCapture(repeated, pid: 0, placement: rightSelection)
        let actualVisible = owner.panel.screen!.visibleFrame
        check(owner.panel.isVisible && owner.currentPlacement?.eventTimestamp == 90
              && owner.panel.frame.origin == rightSelection.origin(in: actualVisible, panelSize: owner.panel.frame.size),
              "a new gesture on the same word applies its frozen opposite-side placement")
        check(owner.question.stringValue == "an unsent question" && owner.messages.count == 1
              && owner.activeGeneration == generation,
              "same-word repositioning preserves the conversation and cannot start a paid request")
        owner.panelController.isPinned = true
        let pinnedOrigin = owner.panel.frame.origin
        owner.currentPlacement = leftSelection
        owner.showWindow(reason: "repeat_selection")
        check(owner.panel.frame.origin == pinnedOrigin, "new content cannot reposition the pinned reading window")
        owner.panelController.isPinned = false
        let chosenOrigin = NSPoint(x: actualVisible.minX + 83, y: actualVisible.minY + 67)
        owner.panel.setFrameOrigin(chosenOrigin)
        let chosenFrame = owner.panel.frame
        owner.panelController.dismiss(reason: "escape")
        owner.openWindow()
        check(owner.panel.frame == chosenFrame, "menu reopen keeps the last position despite stale selection placement")
        owner.panelController.dismiss(reason: "outside_click")
        owner.showWindow(reason: "reopen")
        check(owner.panel.frame == chosenFrame, "application reopen keeps the same position")
        owner.panelController.dismiss(reason: "component_restart")
        let restarted = BookAsk(); restarted.recordSink = { _ in }; restarted.buildWindow()
        check(restarted.hasWindowPosition, "saved frame is restored by a new application owner")
        restarted.showWindow(reason: "launch")
        check(restarted.panel.frame == chosenFrame, "launch honors persisted origin and size")
        restarted.panelController.dismiss(reason: "component_restart_complete")
        check(ReadingPanelController.visibleOrigin(NSPoint(x: -4000, y: 9000), size: size, in: visible)
              == NSPoint(x: visible.minX, y: visible.maxY - size.height), "offscreen restore is clamped to a reachable position")
        owner.showWindow(reason: "explicit_open")
        // Exercise real run-loop elapsed time with the legacy preference ON.
        // A hidden/dead timer must not survive the feature removal.
        RunLoop.current.run(until: Date().addingTimeInterval(15.3))
        check(owner.panel.isVisible, "legacy 15-second preference cannot hide the new panel")
        owner.panelController.dismiss(reason: "component_test_complete")
        print("PASS: frozen selection placement, offset window and multi-screen coordinates; Books outside-click regression, click pass-through, Esc/close, legacy 15s preference ignored with real elapsed time, minimum-width layout and state preservation")
    }
}
