import AppKit

@main
struct ManualPopupInputTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let savedPopup = defaults.object(forKey: "automaticPopupEnabled")
        defer { defaults.set(savedPopup, forKey: "automaticPopupEnabled") }
        defaults.removeObject(forKey: "automaticPopupEnabled")
        precondition(!ReadingPreferences.automaticPopup, "manual popup is the new default")
        let owner = BookAsk()
        owner.recordSink = { _ in }
        owner.autoPopup = false; owner.copyCaptureEnabled = true
        owner.buildWindow()
        owner.windowPresenter = { _ in fatalError("a mere gesture or tap must not front until a confirmed capture") }
        var scheduled: [(Bool, ReadingPanelPlacement?)] = []
        owner.copyScheduleSink = { _, _, placement, manual in scheduled.append((manual, placement)) }
        let placement = ReadingPanelPlacement(mousePoint: NSPoint(x: 800, y: 400), booksFrame: nil,
            screenFrame: NSRect(x: 0, y: 0, width: 1200, height: 900), displayID: nil, eventTimestamp: 1)
        var context = SelectionActionContext(booksPID: 123, trusted: true, mouseButtons: 0)
        owner.actionContextProvider = { context }
        var offered = 0
        owner.actionOfferPresenter = { _ in offered += 1; return true }
        func arm() { owner.handleSelectionGesture(pid: 123, placement: placement) }
        func click() { owner.selectionActionController.button.performClick(nil) }
        for autoExplain in [false, true] {
            owner.autoExplain = autoExplain
            let before = scheduled.count, offersBefore = offered
            arm()
            precondition(offered == offersBefore + 1 && scheduled.count == before && owner.selectedText.isEmpty && owner.activeTask == nil)
            click(); precondition(scheduled.count == before + 1 && scheduled.last!.0)
            precondition(scheduled.last!.1?.mousePoint == placement.mousePoint, "freeze mouse-up geometry until click")
            click(); click()
            precondition(scheduled.count == before + 1, "repeated click cannot reuse a consumed offer")
            owner.autoPopup = true
            arm(); precondition(scheduled.count == before + 2 && !scheduled.last!.0 && offered == offersBefore + 1)
            click(); precondition(scheduled.count == before + 2)
            owner.autoPopup = false
        }
        let before = scheduled.count
        for reason in ["keyboard_input", "mouse_or_scroll", "application_changed", "books_connection_refresh", "local_input"] {
            arm(); owner.activeCaptureID = "pending-test-copy"
            owner.invalidateManualSelection(reason: reason); click()
            precondition(owner.manualIntent.token == nil && owner.activeCaptureID.isEmpty)
        }
        arm(); context.booksPID = 999; click(); context.booksPID = 123
        arm(); owner.selectionInteraction.event(buttons: 0); click()
        arm(); context.mouseButtons = 1; click(); context.mouseButtons = 0
        arm(); context.trusted = false; click(); context.trusted = true
        precondition(scheduled.count == before, "wrong app, changed selection, held mouse and permission loss reject")
        arm(); owner.toggleAutomaticPopup(); click()
        precondition(ReadingPreferences.automaticPopup && owner.manualIntent.token == nil)
        owner.toggleAutomaticPopup(); precondition(!ReadingPreferences.automaticPopup)
        click(); precondition(scheduled.count == before, "mode switch cannot retain stale selection")
        owner.copyCaptureEnabled = false
        arm(); click()
        precondition(scheduled.count == before + 1, "explicit button still uses guarded copy when legacy automatic copy is off")
        let after = scheduled.count
        context.trusted = false; arm(); click(); context.trusted = true
        context.booksPID = nil; arm(); click(); context.booksPID = 123
        context.mouseButtons = 1; arm(); click(); context.mouseButtons = 0
        precondition(scheduled.count == after && owner.manualIntent.token == nil)

        // This is a real native panel/button; test both presentation properties
        // and the previously dangerous mouse-poll path during button tracking.
        let offer = owner.selectionActionController
        precondition(!offer.panel.canBecomeKey && !offer.panel.canBecomeMain && offer.panel.styleMask.contains(.nonactivatingPanel))
        let screen = NSScreen.screens[0].visibleFrame
        let point = NSPoint(x: screen.midX, y: screen.midY)
        arm(); precondition(offer.show(near: point))
        let revision = owner.interactionRevision
        let inside = NSPoint(x: offer.panel.frame.midX, y: offer.panel.frame.midY)
        owner.observeSelectionMouse(buttons: 1, point: inside)
        owner.observeSelectionMouse(buttons: 0, point: inside)
        precondition(owner.interactionRevision == revision && owner.manualIntent.token != nil,
                     "clicking the offer must not invalidate the Books selection")
        click(); precondition(scheduled.count == after + 1 && !offer.panel.isVisible)
        arm(); owner.observeSelectionMouse(buttons: 1, point: .zero); click()
        precondition(scheduled.count == after + 1 && owner.manualIntent.token == nil)
        owner.observeSelectionMouse(buttons: 0, point: .zero)
        for frame in [NSRect(x: 0, y: 0, width: 1200, height: 900), NSRect(x: -1600, y: -900, width: 1600, height: 900)] {
            for x in [frame.minX, frame.midX, frame.maxX] {
                for y in [frame.minY, frame.midY, frame.maxY] {
                    let proposed = SelectionActionController.frame(near: NSPoint(x: x, y: y), in: frame, size: offer.panel.frame.size)
                    precondition(frame.contains(proposed), "offer remains inside selected display")
                }
            }
        }
        // Generated shortcut events are constructed, never posted to another
        // app. Only our tagged fallback may survive the keyboard cancel gate.
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)!
        key.flags = .maskCommand
        key.setIntegerValueField(.eventSourceUserData, value: BooksCopy.copyEventTag)
        owner.activeCaptureID = "copy-under-test"
        owner.handleDismissKey(NSEvent(cgEvent: key)!)
        precondition(owner.activeCaptureID == "copy-under-test")
        let physicalKey = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)!
        physicalKey.flags = .maskCommand
        precondition(!BooksCopy.isOwnCopyEvent(NSEvent(cgEvent: physicalKey)!))
        owner.handleDismissKey(NSEvent(cgEvent: physicalKey)!)
        precondition(owner.activeCaptureID.isEmpty, "real user copy cancels pending manual capture")

        let long = "START " + String(repeating: "Please explain this English expression. 这段话的用法是什么？\n", count: 30) + " END"
        for width in [500.0, 640.0, 900.0, 500.0] {
            owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: width, height: 539), display: false)
            owner.question.stringValue = "A short question"
            owner.readingContent.layoutSubtreeIfNeeded(); owner.updateQuestionHeight(); owner.readingContent.layoutSubtreeIfNeeded()
            precondition(owner.questionHeight.constant == 43)
            owner.question.stringValue = long
            owner.readingContent.layoutSubtreeIfNeeded(); owner.updateQuestionHeight(); owner.readingContent.layoutSubtreeIfNeeded()
            let view = owner.question!, scroll = owner.questionScroll!
            view.layoutManager!.ensureLayout(for: view.textContainer!)
            precondition(owner.questionHeight.constant == 90)
            precondition(view.stringValue == long && view.frame.height > scroll.contentSize.height)
            precondition(!scroll.hasHorizontalScroller && scroll.hasVerticalScroller)
            let used = view.layoutManager!.usedRect(for: view.textContainer!)
            precondition(used.maxX <= scroll.contentSize.width + 1)
            view.scrollRangeToVisible(NSRange(location: (long as NSString).length - 3, length: 3))
            precondition(scroll.contentView.bounds.minY > 0, "can reach the end of long input")
            view.scrollRangeToVisible(NSRange(location: 0, length: 5))
            precondition(scroll.contentView.bounds.minY < 5, "can return to the start")
            precondition(!scroll.convert(scroll.bounds, to: owner.readingContent).intersects(owner.transcript.enclosingScrollView!.frame))
            precondition(owner.popupButton.frame.maxX <= owner.automaticButton.frame.minX + 0.5,
                         "toggle frames overlap: \(owner.popupButton.frame) / \(owner.automaticButton.frame)")
            precondition(owner.automaticButton.frame.maxX < owner.smallerAnswerButton.frame.minX)
            precondition(abs(owner.popupButton.frame.midY - owner.automaticButton.frame.midY) < 0.5)
            precondition(owner.popupButton.frame.width + 0.5 >= owner.popupButton.intrinsicContentSize.width)
            precondition(owner.automaticButton.frame.width + 0.5 >= owner.automaticButton.intrinsicContentSize.width)
            precondition(owner.transcript.enclosingScrollView!.frame.height > 65)
        }
        var sent = 0
        owner.question.onSubmit = { sent += 1 }
        func enter(_ modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: owner.panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        }
        owner.question.stringValue = "hello"; owner.question.setSelectedRange(NSRange(location: 5, length: 0))
        owner.question.keyDown(with: enter(.shift))
        precondition(sent == 0 && owner.question.stringValue.contains("\n"))
        owner.question.keyDown(with: enter([])); precondition(sent == 1)
        owner.question.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        owner.question.keyDown(with: enter([])); precondition(sent == 1, "IME confirmation must not send")
        owner.question.unmarkText()
        owner.question.stringValue = ""; owner.readingContent.layoutSubtreeIfNeeded(); owner.updateQuestionHeight()
        precondition(owner.questionHeight.constant == 43)
        if let output = ProcessInfo.processInfo.environment["BOOKASK_RENDER_DIR"] {
            owner.question.stringValue = String(repeating: "Could you explain how this expression changes the meaning of the sentence? ", count: 8)
            owner.quote.string = "The truth is down there somewhere, but it’s fragile."
            owner.transcript.string = "The truth is fragile here because a leading question can influence the answer. Ask in a way that lets someone describe their real experience."
            PaperTheme.apply(.dark, to: owner.panel)
            owner.readingContent.layoutSubtreeIfNeeded(); owner.updateQuestionHeight(); owner.readingContent.layoutSubtreeIfNeeded()
            let bitmap = owner.readingContent.bitmapImageRepForCachingDisplay(in: owner.readingContent.bounds)!
            owner.readingContent.cacheDisplay(in: owner.readingContent.bounds, to: bitmap)
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("long-input.png"))
            for appearance in [ReadingAppearance.light, .dark] {
                PaperTheme.apply(appearance, to: offer.panel)
                let image = offer.button.bitmapImageRepForCachingDisplay(in: offer.button.bounds)!
                offer.button.cacheDisplay(in: offer.button.bounds, to: image)
                try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("selection-action-\(appearance.rawValue).png"))
            }
        }
        print("PASS: default/persisted independent popup mode; zero work until action click; stale gestures and modes rejected; nonactivating offer and mouse polling; tagged copy fallback; frozen placement; multiline height/wrapping/scrolling at 500/640/900pt; Return, Shift+Return and IME confirmation")
    }
}
