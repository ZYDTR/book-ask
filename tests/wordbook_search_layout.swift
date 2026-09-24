import AppKit

/// Exercise AppKit's real field editor; an unfocused field alone misses this regression.
@main struct WordbookSearchLayoutTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wordbook-search-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WordbookLibrary(url: root.appendingPathComponent("wordbook.json"), historyURL: root.appendingPathComponent("history.jsonl"))
        _ = try await library.save("fragile", book: "Sample", exchange: .init(question: "Explain", answer: "Easily damaged. 易碎的。", automatic: true), time: "2026-09-24")
        _ = try await library.save("bank", book: "Sample", exchange: .init(question: "Explain", answer: "The side of a river.", automatic: true), time: "2026-09-24")
        let page = WordbookView(fallbackBook: "Sample", library: library)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 360, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = page
        window.makeKeyAndOrderFront(nil)
        let search = page.subviews.compactMap { $0 as? NSSearchField }.first!
        let table = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTableView }.first!
        if CommandLine.arguments.contains("--old-borderless") { search.isBezeled = false }
        if CommandLine.arguments.contains("--old-no-scroll") { search.cell?.isScrollable = false }
        var output: URL?
        if let i = CommandLine.arguments.firstIndex(of: "--render-dir") {
            output = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            try FileManager.default.createDirectory(at: output!, withIntermediateDirectories: true)
        }
        func require(_ valid: Bool, _ message: String) {
            if !valid { print("FAIL: " + message); exit(1) }
        }
        func render(_ name: String) throws {
            guard let output else { return }
            page.layoutSubtreeIfNeeded(); page.displayIfNeeded()
            let bitmap = page.bitmapImageRepForCachingDisplay(in: page.bounds)!
            page.cacheDisplay(in: page.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func checkEditor() -> NSTextView {
            require(search.currentEditor() is NSTextView, "search remains editable")
            let editor = search.currentEditor() as! NSTextView
            let visible = search.convert(editor.visibleRect, from: editor)
            let padding = editor.textContainer!.lineFragmentPadding
            require(visible.minX + padding > search.searchButtonBounds.maxX,
                    "focused text/caret overlaps magnifier: editor \(visible), icon \(search.searchButtonBounds)")
            require(visible.maxX - padding <= search.cancelButtonBounds.minX,
                    "focused text overlaps clear button")
            require(abs(visible.midY - search.searchButtonBounds.midY) < 2, "text and magnifier align vertically")
            return editor
        }
        page.open()
        let deadline = Date().addingTimeInterval(5)
        while table.numberOfRows != 2 && Date() < deadline { await Task.yield() }
        require(table.numberOfRows == 2, "isolated entries loaded")
        let savedStyle = UserDefaults.standard.object(forKey: "readingStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "readingStyle") }
        for style: ReadingStyle in [.books, .paper] {
            ReadingPreferences.setStyle(style); page.refreshStyle()
            for appearance: ReadingAppearance in [.light, .dark] {
                PaperTheme.apply(appearance, to: window)
                for width in [360, 640] {
                    window.makeFirstResponder(nil)
                    search.stringValue = ""
                    page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
                    window.setContentSize(NSSize(width: width, height: 340))
                    page.layoutSubtreeIfNeeded()
                    let label = "\(style.rawValue)-\(appearance.rawValue)-\(width)"
                    try render(label + "-empty")
                    window.makeFirstResponder(search)
                    let editor = checkEditor()
                    try render(label + "-focused")
                    editor.insertText("fragile", replacementRange: NSRange(location: 0, length: 0))
                    require(search.stringValue == "fragile" && table.numberOfRows == 1, "native editing filters immediately")
                    _ = checkEditor()
                    try render(label + "-typing")
                    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                    editor.insertText("易碎", replacementRange: editor.selectedRange())
                    require(search.stringValue == "易碎" && table.numberOfRows == 1, "Chinese explanation search works")
                    editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
                    editor.insertText(String(repeating: "long search phrase ", count: 20), replacementRange: editor.selectedRange())
                    editor.scrollRangeToVisible(editor.selectedRange())
                    window.displayIfNeeded()
                    _ = checkEditor()
                    let manager = editor.layoutManager!
                    manager.ensureLayout(for: editor.textContainer!)
                    let lastGlyph = manager.glyphRange(forCharacterRange: NSRange(location: editor.string.utf16.count - 1, length: 1), actualCharacterRange: nil)
                    let lastRect = manager.boundingRect(forGlyphRange: lastGlyph, in: editor.textContainer!).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                    require(lastRect.width > 0 && editor.visibleRect.contains(lastRect), "long query must scroll to keep the final character visible: glyph \(lastRect), visible \(editor.visibleRect)")
                    try render(label + "-long")
                    let cell = search.cell as! NSSearchFieldCell
                    cell.cancelButtonCell!.performClick(search)
                    require(search.stringValue.isEmpty && table.numberOfRows == 2, "native clear restores all terms")
                    window.makeFirstResponder(search)
                    _ = checkEditor()
                    try render(label + "-cleared")
                }
            }
        }
        print("PASS: actual native field editor, icon/caret/clear separation, typing/filtering, Chinese query, long text and clearing; 4 themes at 360/640pt")
    }
}
