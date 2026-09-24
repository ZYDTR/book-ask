import AppKit

@main struct WordbookLayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let content = WordbookView(fallbackBook: "Book")
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 500, height: 511),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = content
        for width in [360, 500, 640, 900, 500] {
            let height = width == 360 ? 340.0 : 511.0
            window.setContentSize(NSSize(width: Double(width), height: height))
            content.layoutSubtreeIfNeeded()
            precondition(abs(content.frame.height - height) < 1, "Wordbook page must fill the existing window")
            let scrolls = content.subviews.compactMap { $0 as? NSScrollView }
            precondition(scrolls.count == 2 && scrolls.allSatisfy { $0.frame.height > (width == 360 ? 144 : 315) }, "wordbook scroll frames at \(width): \(scrolls.map { NSStringFromRect($0.frame) })")
            precondition(!content.isShowingDetail, "initial page is the term list")
            for scroll in scrolls {
                precondition(!scroll.hasHorizontalScroller)
                if let text = scroll.documentView as? NSTextView {
                    text.string = String(repeating: "A lengthy explanation that must wrap naturally. 中文释义 ", count: 60)
                    text.layoutManager?.ensureLayout(for: text.textContainer!)
                    precondition(abs(text.frame.width - scroll.contentSize.width) < 1)
                    let shifted = scroll.contentView.constrainBoundsRect(NSRect(x: 100, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height))
                    precondition(abs(shifted.minX) < 1, "detail cannot scroll horizontally")
                }
            }
        }
        print("PASS: same-window wordbook page fills 360/500/640/900pt; list/detail stay readable and text wraps")
    }
}
