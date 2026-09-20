import AppKit

/// Uses the real window with clearly isolated sample content; never runs capture
/// or model requests. Optional PNGs are component renders, not Books E2E proof.
@main struct ReadingVisualLayoutTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let owner = BookAsk()
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
            let pixel = bitmap().colorAt(x: 4, y: 4)!.usingColorSpace(.sRGB)!
            assertThat(choice == .dark ? pixel.redComponent < 0.25 : pixel.redComponent > 0.9,
                       "rendered paper cache must update after every theme switch")
            assertThat(owner.question.stringValue == draft && owner.transcript.string == answer && owner.promptEditor.string == prompt,
                       "theme changes preserve draft, explanation and custom prompt")
            assertThat(owner.activeGeneration == generation && owner.sessionId == session, "theme does not reset a model request or session")
            try render(choice.rawValue + "-answer")
        }
        PaperTheme.apply(.system, to: owner.panel)
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: name)
            let pixel = bitmap().colorAt(x: 4, y: 4)!.usingColorSpace(.sRGB)!
            assertThat(owner.panel.appearance == nil, "system mode must inherit appearance")
            assertThat(name == .darkAqua ? pixel.redComponent < 0.25 : pixel.redComponent > 0.9,
                       "system appearance updates the actual paper texture without reopening")
        }
        PaperTheme.apply(.dark, to: owner.panel)
        let long = String(repeating: "Long English phrases and 中文内容 should wrap without hiding the controls. ", count: 50)
            + "https://example.com/" + String(repeating: "unbroken", count: 120)
        for width in [500.0, 640.0, 900.0, 500.0] {
            owner.panel.setFrame(NSRect(x: -20000, y: -20000, width: width, height: 539), display: false)
            for expanded in [false, true] {
                if owner.promptExpanded != expanded { owner.togglePromptEditor() }
                owner.quote.string = long; owner.transcript.string = long
                owner.panel.contentView!.layoutSubtreeIfNeeded()
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
                let controls = [owner.automaticButton!, owner.autoDismissButton!, owner.promptDisclosure!]
                for control in controls {
                    assertThat(control.frame.width + 0.5 >= control.intrinsicContentSize.width, "control label must remain complete")
                }
                let quoteRect = owner.quote.enclosingScrollView!.frame
                let answerRect = owner.transcript.enclosingScrollView!.frame
                assertThat(!quoteRect.intersects(answerRect), "original and answer must not overlap")
                assertThat(answerRect.height >= 65, "answer must remain readable with editor open")
            }
        }
        owner.quote.string = "The truth is down there somewhere, but it’s fragile."
        owner.transcript.string = "The truth is fragile here because a leading question can influence the answer. Ask in a way that lets someone describe their real experience.\n\nTheir trust was fragile, so we chose our words carefully."
        try render("prompt-expanded")
        owner.togglePromptEditor()
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
        print("PASS: system/light/dark rendering, repeated cached theme switches, persisted choice, preserved draft/session/prompt; UI at 500/640/900pt, expanded/collapsed prompt, long English/Chinese/URL and no horizontal scroll")
    }
}
