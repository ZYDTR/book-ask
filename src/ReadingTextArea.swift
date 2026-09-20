import AppKit

enum ReadingTextArea {
    static func make(font: NSFont, height: CGFloat) -> (NSScrollView, NSTextView) {
        // Start the viewport and its document at the same width. A zero-width
        // scroll view with a 540pt document would retain that 540pt excess when
        // Auto Layout later expands the viewport.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let view = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        view.isEditable = false
        view.isSelectable = true
        view.font = font
        view.textColor = .labelColor
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: max(0, view.bounds.width - 16), height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.paragraphSpacing = 8
        view.defaultParagraphStyle = paragraph
        scroll.documentView = view
        return (scroll, view)
    }

}
