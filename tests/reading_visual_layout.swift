import AppKit

/// Uses the real window with clearly isolated sample content; never runs capture
/// or model requests. Optional PNGs are component renders, not Books E2E proof.
@main struct ReadingVisualLayoutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let savedStyle = UserDefaults.standard.object(forKey: "readingStyle")
        ReadingPreferences.setStyle(.books)
        defer { UserDefaults.standard.set(savedStyle, forKey: "readingStyle") }
        let owner = BookAsk()
        owner.recordSink = { _ in }
        owner.buildWindow()
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        let renderIndex = CommandLine.arguments.firstIndex(of: "--render-dir")
        let output = renderIndex.map { URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        func assertThat(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func bitmap() -> NSBitmapImageRep {
            let view = owner.panel.contentView!
            view.displayIfNeeded()
            let result = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: result)
            return result
        }
        func render(_ name: String) throws {
            guard let output else { return }
            try bitmap().representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        let suite = "BookAsk.ThemeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assertThat(ReadingPreferences.appearance(in: defaults) == .system, "first launch follows system")
        ReadingPreferences.setAppearance(.dark, in: defaults)
        assertThat(ReadingPreferences.appearance(in: UserDefaults(suiteName: suite)!) == .dark, "explicit theme persists")
        defaults.set("unknown-future-theme", forKey: "paperAppearance")
        assertThat(ReadingPreferences.appearance(in: defaults) == .system, "invalid preference falls back safely")
        assertThat(ReadingPreferences.style(in: defaults) == .paper, "first launch defaults to paper E")
        ReadingPreferences.setStyle(.books, in: defaults)
        assertThat(ReadingPreferences.style(in: UserDefaults(suiteName: suite)!) == .books, "style choice survives preference reload")
        assertThat(ReadingPreferences.answerFontSize(in: defaults) == 17, "first launch defaults to 17pt")
        ReadingPreferences.setAnswerFontSize(19, in: defaults)
        assertThat(ReadingPreferences.answerFontSize(in: UserDefaults(suiteName: suite)!) == 19, "answer size survives preference reload")
        ReadingPreferences.setAnswerFontSize(100, in: defaults)
        assertThat(ReadingPreferences.answerFontSize(in: defaults) == 24, "font max prevents unusable scale")
        ReadingPreferences.setAnswerFontSize(-5, in: defaults)
        assertThat(ReadingPreferences.answerFontSize(in: defaults) == 13, "font min remains readable")
        PaperTheme.apply(.light, to: owner.panel)
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        try render("empty")
        owner.quote.string = "you’re liable to"
        owner.contextLabel.stringValue = "The Mom Test · 已关联所在段落与前后文"
        owner.transcript.string = "You’re liable to means something is likely to happen, especially an unwanted result. Here, careless questions can damage your chance of learning the truth.\n\nIf you only ask for compliments, you’re liable to miss what your customers really need."
        owner.status.stringValue = "gemini-3.7-flash · 已完成 · 可继续追问"
        owner.question.stringValue = "How is this different from likely to?"
        try render("short-answer")
        let draft = owner.question.stringValue, answer = owner.transcript.string, prompt = owner.promptEditor.string
        let generation = owner.activeGeneration, session = owner.sessionId
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        // Repeated switching checks the actual cached background, not just enum values.
        for choice: ReadingAppearance in [.dark, .light, .dark] {
            PaperTheme.apply(choice, to: owner.panel)
            let pixel = bitmap().colorAt(x: 24, y: 450)!.usingColorSpace(.sRGB)!
            assertThat(choice == .dark ? pixel.redComponent < 0.25 : pixel.redComponent > 0.9,
                       "rendered paper cache must update after every theme switch: \(choice) pixel=\(pixel)")
            assertThat(owner.question.stringValue == draft && owner.transcript.string == answer && owner.promptEditor.string == prompt,
                       "theme changes preserve draft, explanation and custom prompt")
            assertThat(owner.activeGeneration == generation && owner.sessionId == session, "theme does not reset a model request or session")
            try render(choice.rawValue + "-answer")
        }
        let savedSize = UserDefaults.standard.object(forKey: "answerFontSize")
        defer { UserDefaults.standard.set(savedSize, forKey: "answerFontSize") }
        owner.answerFontSize = 17
        let prefix = NSMutableAttributedString(attributedString: owner.conversationText("A saved answer.\n\n"))
        prefix.append(owner.conversationText("你：How is it different?\n\n", isQuestion: true))
        owner.displayHistory = prefix
        owner.showConversation(prefix, answer: "A partial response.")
        let fixedButtonFont = owner.automaticButton.font!
        let fixedInputFont = owner.question.font!, savedMessages = owner.messages
        for size in [19.0, 13.0, 24.0, 17.0] {
            owner.changeAnswerSize(to: size)
            // A callback holding the OLD prefix arrives after the user changes size.
            owner.displayHistory = owner.showConversation(prefix, answer: "A completed response.")
            let rendered = owner.transcript.attributedString()
            rendered.enumerateAttribute(.font, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
                let font = value as! NSFont
                assertThat(font.pointSize == size, "all response runs use chosen reading face/size, including stale streaming prefix: \(font.fontName) \(font.pointSize), expected \(size)")
            }
            assertThat((rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == ".NewYork-Regular", "English body resolves to dynamic New York; Chinese uses system glyph fallback")
            let questionRange = (rendered.string as NSString).range(of: "你：")
            assertThat((rendered.attribute(.foregroundColor, at: questionRange.location, effectiveRange: nil) as? NSColor) == PaperTheme.coral,
                       "size changes preserve question color")
            assertThat(owner.quote.font?.pointSize == CGFloat(size) && owner.automaticButton.font == fixedButtonFont && owner.question.font == fixedInputFont,
                       "original and answer share size while controls and input stay fixed")
            assertThat(owner.question.stringValue == draft && owner.messages == savedMessages && owner.activeGeneration == generation,
                       "size changes preserve unsent draft/model history/generation")
            assertThat(ReadingPreferences.answerFontSize() == size, "current size is persisted")
        }
        assertThat(bitmap().colorAt(x: 0, y: 0)!.alphaComponent < 0.01, "paper corners are actually transparent")
        owner.restoreWordbook(WordbookEntry(selection: "you’re liable to", book: "The Mom Test", latestTime: "2026-09-20", exchanges: [
            WordbookExchange(question: "Explain", answer: "Likely to do something or experience something, especially an unwanted result.\n\nIf you rush the interview, you’re liable to miss an important detail.", automatic: true),
            WordbookExchange(question: "How is it different from likely to?", answer: "Liable to often suggests a risk or an unwanted outcome. Likely to is more neutral.", automatic: false)]))
        owner.question.stringValue = ""
        try render("books-17")
        owner.changeAnswerSize(to: 19)
        try render("books-19")
        owner.changeAnswerSize(to: 17)
        let styleDraft = owner.question.stringValue, styleText = owner.transcript.string, quoteText = owner.quote.string
        let styleMessages = owner.messages
        for style: ReadingStyle in [.paper, .books, .paper] {
            owner.setReadingStyle(style)
            assertThat(ReadingPreferences.style() == style, "visual style persists")
            assertThat(owner.transcript.string == styleText && owner.quote.string == quoteText && owner.question.stringValue == styleDraft,
                       "style switch preserves conversation, original and draft")
            assertThat(owner.activeGeneration == generation && owner.messages == styleMessages, "style switch cannot restart generation")
            let attrs = owner.transcript.attributedString()
            let font = attrs.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
            assertThat(font.fontName == PaperTheme.readingFont(17).fontName && font.pointSize == 17, "style resolves correct family and existing size")
            let q = (attrs.string as NSString).range(of: "你：")
            assertThat((attrs.attribute(.foregroundColor, at: q.location, effectiveRange: nil) as? NSColor) == PaperTheme.coral,
                       "style switch preserves question role tint")
            let pixel = bitmap().colorAt(x: 24, y: 450)!.usingColorSpace(.sRGB)!
            assertThat(style == .books ? pixel.redComponent < 0.02 : pixel.redComponent > 0.12, "native uses black; paper returns to textured green")
            try render(style.rawValue + "-17")
        }
        PaperTheme.apply(.system, to: owner.panel)
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: name)
            let pixel = bitmap().colorAt(x: 24, y: 450)!.usingColorSpace(.sRGB)!
            assertThat(owner.panel.appearance == nil, "system mode must inherit appearance")
            assertThat(name == .darkAqua ? pixel.redComponent < 0.25 : pixel.redComponent > 0.9,
                       "system appearance updates the actual paper texture without reopening")
            try render(name == .darkAqua ? "paper-dark" : "paper-light")
        }
        PaperTheme.apply(.dark, to: owner.panel)
        let long = String(repeating: "Long English phrases and 中文内容 should wrap without hiding the controls. ", count: 50)
            + "https://example.com/" + String(repeating: "unbroken", count: 120)
        for width in [500.0, 420.0, 360.0, 640.0, 900.0, 500.0] {
            owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: width, height: width <= 420 ? (width == 360 ? 340 : 400) : 539), display: false)
            for expanded in [false, true] {
                if owner.promptExpanded != expanded { owner.togglePromptEditor() }
                owner.quote.string = long; owner.transcript.string = long
                owner.panel.contentView!.layoutSubtreeIfNeeded()
                assertThat(abs(owner.panel.frame.width - width) < 1, "toolbar must not force requested window wider")
                let scrolls = owner.panel.contentView!.subviews.compactMap { $0 as? NSScrollView }
                for scroll in scrolls where !scroll.isHidden {
                    assertThat(scroll.frame.height > 45, "expanded editor must leave useful room for reading at \(width)")
                    let text = scroll.documentView as! NSTextView
                    text.layoutManager?.ensureLayout(for: text.textContainer!)
                    assertThat(abs(text.frame.width - scroll.contentSize.width) < 1, "text width must match viewport")
                    let shifted = scroll.contentView.constrainBoundsRect(NSRect(x: 100, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height))
                    assertThat(abs(shifted.minX) < 1, "paper text surfaces must reject horizontal scroll")
                    let used = text.layoutManager!.usedRect(for: text.textContainer!)
                    assertThat(used.maxX + text.textContainerInset.width * 2 <= scroll.contentSize.width + 1,
                               "long unbroken text must stay inside paper surface")
                }
                let controls = [owner.automaticButton!, owner.smallerAnswerButton!, owner.largerAnswerButton!, owner.styleButton!, owner.promptDisclosure!]
                for control in controls {
                    assertThat(control.frame.width + 0.5 >= control.intrinsicContentSize.width, "control label must remain complete")
                }
                let quoteRect = owner.quote.frame
                assertThat(owner.quote.enclosingScrollView == nil, "original excerpt has no scroll surface")
                assertThat(abs(quoteRect.height - owner.quote.excerptHeight) < 0.5, "original reserves two full lines and paper padding")
                assertThat(owner.quote.string == long, "display truncation must preserve the full original")
                let layout = owner.quote.layoutManager!, container = owner.quote.textContainer!
                layout.ensureLayout(for: container)
                let glyphs = layout.glyphRange(for: container)
                var lines = 0, hasEllipsis = false
                layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
                    lines += 1
                    assertThat(rect.maxY <= owner.quote.excerptLineHeight * 2 + 0.5, "both excerpt lines fit without clipping")
                    if layout.truncatedGlyphRange(inLineFragmentForGlyphAt: range.location).location != NSNotFound {
                        hasEllipsis = true
                    }
                }
                assertThat(lines == 2 && hasEllipsis, "long original renders two lines with a tail ellipsis")
                let answerRect = owner.transcript.enclosingScrollView!.frame
                assertThat(!quoteRect.intersects(answerRect), "original and answer must not overlap")
                assertThat(answerRect.height >= 65, "answer must remain readable with editor open")
                if !expanded { try render("selection-two-lines-\(Int(width))") }
            }
        }
        if owner.promptExpanded { owner.closePromptEditor(save: false) }
        owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: 360, height: 340), display: false)
        owner.changeAnswerSize(to: 24)
        owner.question.stringValue = String(repeating: "A long follow-up question with several lines. ", count: 8)
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        owner.question.layoutManager?.ensureLayout(for: owner.question.textContainer!)
        owner.updateQuestionHeight()
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        assertThat(owner.transcript.enclosingScrollView!.frame.height >= 45, "maximum reading size and long input retain a scrollable answer at minimum window size")
        assertThat(owner.questionScroll.frame.height >= 22 && owner.sendButton.frame.height == 32, "minimum size retains input and send action")
        try render("minimum-stress-24")
        owner.changeAnswerSize(to: 17)
        owner.question.stringValue = ""
        owner.answerSizeLabel.isHidden = true
        owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: 500, height: 539), display: false)
        let savedPromptPreference = UserDefaults.standard.object(forKey: "explanationPrompt")
        defer { UserDefaults.standard.set(savedPromptPreference, forKey: "explanationPrompt") }
        let acceptedPrompt = owner.promptEditor.string
        owner.togglePromptEditor()
        owner.promptDraftEditor!.string = "uncommitted draft"
        assertThat(owner.promptEditor.string == acceptedPrompt, "draft cannot enter requests before Save")
        owner.closePromptEditor(save: false)
        assertThat(owner.promptEditor.string == acceptedPrompt, "Cancel preserves the accepted template")
        owner.togglePromptEditor()
        owner.promptDraftEditor!.string = acceptedPrompt + "\nTest sentence."
        owner.closePromptEditor(save: true)
        assertThat(owner.promptEditor.string == ReadingPreferences.prompt && ReadingPreferences.prompt.hasSuffix("Test sentence."), "Save updates the request template and persistent preference together")
        owner.promptEditor.string = acceptedPrompt
        owner.quote.string = "The truth is down there somewhere, but it’s fragile."
        owner.transcript.string = "The truth is fragile here because a leading question can influence the answer. Ask in a way that lets someone describe their real experience.\n\nTheir trust was fragile, so we chose our words carefully."
        owner.togglePromptEditor()
        owner.promptPanel?.contentView?.layoutSubtreeIfNeeded()
        if let output, let view = owner.promptPanel?.contentView {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("prompt-editor.png"))
        }
        owner.closePromptEditor(save: false)
        // These are actual AppKit layouts, deliberately showing a retained
        // oversized draft at the minimum supported window size.
        owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: 360, height: 340), display: false)
        owner.question.stringValue = String(repeating: "A long question 字 ", count: 313)
        for style: ReadingStyle in [.books, .paper] {
            ReadingPreferences.setStyle(style); owner.updateReadingStyle()
            for appearance: ReadingAppearance in [.light, .dark] {
                PaperTheme.apply(appearance, to: owner.panel)
                _ = owner.validateRequestInput(owner.question.string, automatic: false)
                owner.panel.contentView!.layoutSubtreeIfNeeded()
                try render("input-limit-" + style.rawValue + "-" + appearance.rawValue)
                assertThat(owner.status.intrinsicContentSize.width <= owner.status.frame.width,
                           "5000-character rejection fits completely at 360pt")
                let statusAlignment = owner.status.alignmentRect(forFrame: owner.status.frame)
                assertThat(owner.panel.frame.width == 360 && statusAlignment.maxX <= 334,
                           "full-width status does not widen the minimum window")
            }
        }
        owner.togglePromptEditor()
        owner.promptDraftEditor!.string = String(repeating: "解释这个表达。", count: 834)
        owner.savePrompt()
        owner.promptPanel?.contentView?.layoutSubtreeIfNeeded()
        assertThat(owner.promptGuidanceLabel!.intrinsicContentSize.width <= owner.promptGuidanceLabel!.frame.width,
                   "prompt Save rejection is fully visible")
        if let output, let view = owner.promptPanel?.contentView {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("prompt-limit.png"))
        }
        owner.cancelPrompt()
        owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: 500, height: 539), display: false)
        owner.question.stringValue = ""
        owner.quote.string = "you’re liable to"
        owner.setBusy(true)
        owner.transcript.string = "You’re liable to means something is likely to happen…"
        owner.status.stringValue = "gemini-3.7-flash · 正在回答"
        try render("streaming")
        owner.setBusy(false)
        owner.transcript.string = "请求未完成：网络连接暂时不可用。\n可在输入框留空时点击「发送」重试。"
        owner.status.stringValue = "请求未完成"
        try render("error")
        print("PASS: New York / SF / Charter style switching; answer font 13–24pt, persisted size, shared quote/answer size, frozen control/input fonts, stale stream prefixes and role colors; system/light/dark rendering, repeated cached theme switches, persisted choice, preserved draft/session/prompt; UI at 360/420/500/640/900pt, expanded/collapsed prompt, long English/Chinese/URL and no horizontal scroll")
    }
}
