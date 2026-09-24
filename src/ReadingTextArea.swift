import AppKit

enum ReadingTextArea {
    static func make(font: NSFont, height: CGFloat, textView: NSTextView? = nil) -> (NSScrollView, NSTextView) {
        // Start the viewport and its document at the same width. A zero-width
        // scroll view with a 540pt document would retain that 540pt excess when
        // Auto Layout later expands the viewport.
        let scroll = ReadingScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let view = textView ?? NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        view.frame = NSRect(origin: .zero, size: scroll.contentSize)
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

/// Native multiline editing keeps IME composition, undo, selection and scrolling.
final class ReadingQuestionView: NSTextView {
    var onContentLayout: (() -> Void)?
    var onSubmit: (() -> Void)?
    var placeholderAttributedString = NSAttributedString(string: "") { didSet { needsDisplay = true } }
    // Keeps callers explicit about replacing the whole draft, as with the old field.
    var stringValue: String {
        get { string }
        set { string = newValue; needsDisplay = true; onContentLayout?() }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        onContentLayout?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onContentLayout?() }
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(nil) }
            else { onSubmit?() }
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !hasMarkedText() {
            placeholderAttributedString.draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                                                          y: textContainerInset.height))
        }
    }
}
