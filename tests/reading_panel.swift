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
        let controller = ReadingPanelController(panel: panel, automaticDismissal: false,
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
            controller.didPresent(forSelection: true)
            check(panel.isVisible, "offscreen fixture is ordered in")
        }
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
        clock += 20
        controller.countdownFired(for: controller.presentationID)
        check(panel.isVisible && controller.deadline == nil, "unchecked option never times out")
        controller.setAutomaticDismissal(true)
        let first = controller.presentationID
        clock += 14.9
        controller.countdownFired(for: first)
        check(panel.isVisible, "15 seconds cannot fire early")
        clock += 0.1
        controller.countdownFired(for: first)
        check(!panel.isVisible, "checked option hides at 15 seconds")

        show()
        let old = controller.presentationID
        clock += 10
        show()
        let next = controller.presentationID
        clock += 5
        controller.countdownFired(for: old)
        check(panel.isVisible, "old word's timer cannot close the next word")
        clock += 10
        controller.countdownFired(for: next)
        check(!panel.isVisible, "new word gets its own full 15 seconds")

        show()
        let beforeInteraction = controller.presentationID
        controller.userInteracted()
        clock += 30
        controller.countdownFired(for: beforeInteraction)
        check(panel.isVisible && controller.deadline == nil,
              "typing/selecting/scrolling cancels this presentation's timeout")
        show()
        check(controller.deadline != nil, "next selection reenables countdown without changing the checkbox")
        let beforeOff = controller.presentationID
        controller.setAutomaticDismissal(false)
        clock += 30
        controller.countdownFired(for: beforeOff)
        check(panel.isVisible, "unchecking cancels even a queued callback")
        controller.outsideClick(timestamp: clock - 40, source: "queued_old_click")
        check(panel.isVisible, "queued mouse-down from before presentation cannot instantly hide it")
        controller.dismiss(reason: "test_complete")
        controller.stopMonitoring()

        // Exercise the actual application window layout at the user's minimum
        // size. All four controls must fit rather than silently clipping text.
        let owner = BookAsk()
        owner.buildWindow()
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        let controls = [owner.automaticButton!, owner.autoDismissButton!, owner.promptDisclosure!]
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
        owner.panelController.dismiss(reason: "component_test_complete")
        print("PASS: frozen selection placement, offset window and multi-screen coordinates; Books outside-click regression, click pass-through, Esc/close, 15s deadline, old-timer isolation, interaction/off cancellation, minimum-width layout and state preservation")
    }
}
