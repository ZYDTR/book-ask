import AppKit

/// Immutable geometry from the selection's mouse-up, carried with that capture.
/// No cursor lookup is needed after the copy delay or while the model responds.
struct ReadingPanelPlacement {
    enum Side: String { case left, right }
    let mousePoint: NSPoint
    let referenceFrame: NSRect
    let referenceSource: String
    let displayID: UInt32?
    let eventTimestamp: TimeInterval
    let side: Side

    init(mousePoint: NSPoint, booksFrame: NSRect?, screenFrame: NSRect,
         displayID: UInt32?, eventTimestamp: TimeInterval) {
        self.mousePoint = mousePoint
        let validFrame = booksFrame.flatMap { frame -> NSRect? in
            frame.width > 0 && frame.height > 0 && frame.contains(mousePoint) ? frame : nil
        }
        referenceFrame = validFrame ?? screenFrame
        referenceSource = validFrame == nil ? "screen" : "books_window"
        self.displayID = displayID
        self.eventTimestamp = eventTimestamp
        side = mousePoint.x >= referenceFrame.midX ? .left : .right
    }

    static func fromQuartz(_ point: CGPoint, primaryScreenTop: CGFloat) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenTop - point.y)
    }

    @MainActor static func capture(mouseUp: NSEvent, booksPID: pid_t) -> ReadingPanelPlacement? {
        guard let point = mouseUp.cgEvent?.location,
              let primary = NSScreen.screens.first else { return nil }
        let mouse = fromQuartz(point, primaryScreenTop: primary.frame.maxY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return nil }
        // WindowServer bounds avoid reading book text/columns or traversing the
        // AX tree. Only on-screen, normal-level Books windows under this point
        // participate. Missing bounds fall back to the selected display's half.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let bounds = windows.lazy.compactMap { row -> CGRect? in
            guard (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == booksPID,
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let value = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: value as CFDictionary),
                  rect.contains(point) else { return nil }
            return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                          width: rect.width, height: rect.height)
        }.first
        return ReadingPanelPlacement(mousePoint: mouse, booksFrame: bounds, screenFrame: screen.frame,
            displayID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
            eventTimestamp: mouseUp.timestamp)
    }

    func origin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        NSPoint(x: side == .left ? visibleFrame.minX : max(visibleFrame.minX, visibleFrame.maxX - panelSize.width),
                y: max(visibleFrame.minY, visibleFrame.maxY - panelSize.height))
    }

    var diagnostics: [String: Any] {
        ["side": side.rawValue, "mouseUpPoint": NSStringFromPoint(mousePoint),
         "referenceFrame": NSStringFromRect(referenceFrame), "referenceSource": referenceSource,
         "displayID": displayID as Any? ?? "unknown", "eventTimestamp": eventTimestamp]
    }
}
