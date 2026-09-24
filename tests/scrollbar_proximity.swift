import AppKit

/// Isolated AppKit regression. Direct proximity signals test the state machine;
/// they are deliberately not claimed as physical mouse or installation evidence.
@main struct ScrollbarProximityTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func advance(_ seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
        let savedStyle = UserDefaults.standard.object(forKey: "readingStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "readingStyle") }
        let owner = BookAsk(); owner.recordSink = { _ in }; owner.buildWindow()
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        owner.quote.string = "messing about in boats"
        owner.contextLabel.stringValue = "The Wind in the Willows · 样例原文"
        let sample = "Spending time in boats just for pleasure, without a particular plan or destination.\n\nWe spent the afternoon messing about in boats on the lake.\n\n"
        owner.transcript.string = String(repeating: sample, count: 8)
        owner.status.stringValue = "已完成 · 可继续追问"
        owner.question.stringValue = String(repeating: "Could you explain the difference with a simpler example? ", count: 12)
        owner.updateQuestionHeight()
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        owner.transcript.layoutManager?.ensureLayout(for: owner.transcript.textContainer!)
        owner.question.layoutManager?.ensureLayout(for: owner.question.textContainer!)
        let answer = owner.transcript.enclosingScrollView as! ReadingScrollView
        let input = owner.questionScroll as! ReadingScrollView
        answer.reflectScrolledClipView(answer.contentView)
        input.reflectScrolledClipView(input.contentView)
        check(answer.hasVerticalOverflow && input.hasVerticalOverflow, "both independent surfaces overflow")
        check(answer.readingScroller!.frame.width == 18, "native layout reserves a stable 18pt hit area")
        check(answer.readingScroller!.target != nil && answer.readingScroller!.action != nil, "AppKit still owns scroller target/action")
        for width in [240.0, 360.0, 500.0, 900.0] {
            let probe = ReadingScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 120))
            check(abs(probe.proximityRect.width - min(width / 3, 120)) < 0.1, "per-region reveal boundary at \(width)")
        }
        advance(1.1)
        let widthBefore = answer.contentSize.width
        answer.updateProximity(at: NSPoint(x: answer.proximityRect.minX - 1, y: answer.bounds.midY))
        advance(0.2)
        check(answer.readingScroller!.revealAmount == 0, "left of boundary stays hidden")
        answer.updateProximity(at: NSPoint(x: answer.proximityRect.minX + 1, y: answer.bounds.midY))
        advance(0.2)
        check(answer.readingScroller!.revealAmount == 1, "entering broad right region reveals")
        let nearPoint = answer.convert(NSPoint(x: answer.bounds.maxX - 25, y: answer.bounds.midY), to: nil)
        let innerExit = NSEvent.enterExitEvent(with: .mouseExited, location: nearPoint,
            modifierFlags: [], timestamp: 0, windowNumber: owner.panel.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        answer.mouseExited(with: innerExit)
        check(answer.pointerIsNear, "exiting an inner native tracking area must not hide the broad region")
        check(input.readingScroller!.revealAmount == 0, "answer hover does not reveal input")
        check(answer.contentSize.width == widthBefore, "reveal does not reflow text")
        let textPoint = answer.convert(NSPoint(x: answer.proximityRect.minX + 4, y: answer.bounds.midY), to: answer.superview)
        check(answer.hitTest(textPoint) is NSTextView, "wide proximity zone passes selection/editing to text")
        answer.updateProximity(at: nil); advance(0.4)
        check(answer.readingScroller!.revealAmount == 1, "exit grace period does not fade immediately")
        answer.updateProximity(at: NSPoint(x: answer.bounds.maxX - 20, y: answer.bounds.midY))
        advance(0.7)
        check(answer.readingScroller!.revealAmount == 1, "re-entry cancels pending hide")
        answer.setIndicatorDragging(true); answer.updateProximity(at: nil); advance(1.1)
        check(answer.readingScroller!.revealAmount == 1, "drag remains visible outside region")
        answer.setIndicatorDragging(false); advance(1.1)
        check(answer.readingScroller!.revealAmount == 0, "release outside eventually fades")
        answer.contentView.scroll(to: NSPoint(x: 0, y: 150))
        answer.reflectScrolledClipView(answer.contentView); advance(0.2)
        check(answer.readingScroller!.revealAmount == 1 && answer.readingScroller!.doubleValue > 0, "native clip scrolling updates and reveals knob")
        let longAnswer = owner.transcript.string
        owner.transcript.string = "Short."
        owner.transcript.layoutManager?.ensureLayout(for: owner.transcript.textContainer!)
        answer.reflectScrolledClipView(answer.contentView)
        check(!answer.hasVerticalOverflow && answer.readingScroller!.revealAmount == 0, "shrinking content removes stale knob immediately")
        owner.transcript.string = longAnswer
        owner.transcript.layoutManager?.ensureLayout(for: owner.transcript.textContainer!)
        owner.togglePromptEditor()
        check(owner.promptDraftEditor?.enclosingScrollView is ReadingScrollView, "actual prompt panel shares component")
        owner.cancelPrompt()
        let library = WordbookLibrary(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"),
                                      historyURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl"))
        let wordbook = WordbookView(fallbackBook: "Test", library: library)
        let wordScrolls = wordbook.subviews.compactMap { $0 as? NSScrollView }
        check(wordScrolls.count == 2 && wordScrolls.allSatisfy { $0 is ReadingScrollView }, "list and detail both share component")
        let outputIndex = CommandLine.arguments.firstIndex(of: "--render-dir")
        if let outputIndex {
            let output = URL(fileURLWithPath: CommandLine.arguments[outputIndex + 1])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for style: ReadingStyle in [.paper, .books] {
                owner.setReadingStyle(style)
                for appearance: ReadingAppearance in [.light, .dark] {
                    PaperTheme.apply(appearance, to: owner.panel)
                    for width in [360.0, 500.0] {
                        owner.panel.setContentSize(NSSize(width: width, height: width == 360 ? 340 : 539))
                        owner.panel.contentView!.layoutSubtreeIfNeeded()
                        for scroll in [answer, input] {
                            (scroll.documentView as? NSTextView)?.layoutManager?.ensureLayout(for: (scroll.documentView as! NSTextView).textContainer!)
                            scroll.reflectScrolledClipView(scroll.contentView)
                            scroll.updateProximity(at: NSPoint(x: scroll.bounds.maxX - 22, y: scroll.bounds.midY))
                        }
                        advance(0.2)
                        let canvas = owner.panel.contentView!
                        let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
                        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(style.rawValue)-\(appearance.rawValue)-\(Int(width)).png"))
                        if width == 500 {
                            let scroller = answer.readingScroller!
                            let knob = scroller.rect(for: .knob)
                            let size = NSSize(width: 32, height: knob.height + 16)
                            let detail = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 4),
                                pixelsHigh: Int(size.height * 4), bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: detail)
                            owner.panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                                let context = NSGraphicsContext.current!.cgContext
                                context.scaleBy(x: 4, y: 4)
                                PaperTheme.paper.setFill(); NSRect(origin: .zero, size: size).fill()
                                context.translateBy(x: 7, y: 8 - knob.minY)
                                scroller.draw(scroller.bounds)
                            }
                            NSGraphicsContext.restoreGraphicsState()
                            try detail.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(style.rawValue)-\(appearance.rawValue)-detail-4x.png"))
                        }
                        check(answer.hasVerticalOverflow && answer.readingScroller!.rect(for: .knob).height > 0, "answer knob remains usable at \(width)")
                        check(input.hasVerticalOverflow && input.readingScroller!.rect(for: .knob).height > 0, "short input knob remains usable at \(width)")
                    }
                }
            }
        }
        print("PASS: native scroller geometry/target, region boundaries, content hit-testing, delayed fade/re-entry, drag lifetime, independent regions, content shrink/growth and all five surfaces")
    }
}
