import AppKit

// Offscreen real AppKit layout: the original replacement content view collapsed
// to 59pt despite a 588pt window, leaving the list and detail at 1pt high.
@main struct WordbookLayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let controller = WordbookWindow(fallbackBook: "Book")
        let window = controller.window!
        for width in [800, 640, 1000] {
            window.setContentSize(NSSize(width: width, height: 560))
            let content = window.contentView!
            content.layoutSubtreeIfNeeded()
            precondition(abs(content.frame.height - 560) < 1, "Wordbook content must fill the window")
            let scrolls = content.subviews.compactMap { $0 as? NSScrollView }
            precondition(scrolls.count == 2 && scrolls.allSatisfy { $0.frame.height > 400 }, "List and explanation must remain visible")
            for scroll in scrolls {
                precondition(!scroll.hasHorizontalScroller)
                if let text = scroll.documentView as? NSTextView {
                    text.string = String(repeating: "A lengthy explanation that must wrap naturally. ", count: 60)
                    text.layoutManager?.ensureLayout(for: text.textContainer!)
                    precondition(abs(text.frame.width - scroll.contentSize.width) < 1)
                }
            }
        }
        print("PASS: wordbook window content fills its frame at 640/800/1000pt; text wraps")
    }
}
