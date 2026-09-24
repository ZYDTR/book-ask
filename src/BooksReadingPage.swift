import AppKit
import ApplicationServices

extension BooksSelection {
    /// Snapshot is taken before our panel takes focus. Copied selection remains
    /// authoritative; AX only contributes a page and a range verified against it.
    static func readingPage(pid: pid_t, selection: String, point: CGPoint? = nil) -> ReadingPageSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(attribute(app, kAXFocusedWindowAttribute)),
              let title = attribute(window, kAXTitleAttribute) as? String, !title.isEmpty else { return nil }
        let needle = ReadingContext.normalize(selection)
        guard !needle.isEmpty else { return nil }
        var queue = [window]; var seen = Set<CFHashCode>(); var candidates = [ReadingPageSnapshot]()
        let deadline = Date().addingTimeInterval(1.2)
        while !queue.isEmpty, seen.count < 400, Date() < deadline {
            let node = queue.removeLast()
            guard seen.insert(CFHash(node)).inserted else { continue }
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            if ["AXStaticText", "AXTextArea", "AXWebArea"].contains(role),
               let value = attribute(node, kAXValueAttribute) as? String,
               value.utf16.count < 150_000, LocalBookIndex.words(value).count >= 8,
               ReadingContext.normalize(value).contains(needle) {
                var selected: NSRange?
                if let raw = attribute(node, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length > 0,
                       range.location + range.length <= (value as NSString).length,
                       ReadingContext.normalize((value as NSString).substring(with: NSRange(location: range.location, length: range.length))) == needle {
                        var positionMatches = true
                        if let point {
                            var boundsValue: CFTypeRef?
                            positionMatches = false
                            if AXUIElementCopyParameterizedAttributeValue(node, "AXBoundsForRange" as CFString, raw, &boundsValue) == .success,
                               let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() {
                                var bounds = CGRect.zero
                                if AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) { positionMatches = bounds.insetBy(dx: -8, dy: -8).contains(point) }
                            }
                        }
                        if positionMatches { selected = NSRange(location: range.location, length: range.length) }
                    }
                }
                let page = ReadingPageSnapshot(bookTitle: title, visibleText: value, selectedRange: selected)
                if selected != nil { return page }
                candidates.append(page)
            }
            let children = (attribute(node, "AXChildrenInNavigationOrder") as? [AXUIElement])
                ?? (attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            queue.append(contentsOf: children.prefix(200).reversed())
        }
        let unique = Dictionary(grouping: candidates, by: { ReadingContext.normalize($0.visibleText) })
        if unique.count == 1 { return unique.values.first?.first }
        return ReadingPageSnapshot(bookTitle: title, visibleText: "", selectedRange: nil)
    }
}
