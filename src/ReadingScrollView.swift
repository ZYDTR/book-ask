import AppKit

/// Native scrolling/editing with a quiet, proximity-revealed indicator. The
/// tracking area observes events; it never sits over selectable content.
final class ReadingScrollView: NSScrollView {
    private(set) var pointerIsNear = false
    private(set) var isDraggingIndicator = false
    private var proximityArea: NSTrackingArea?
    private var hideWork: DispatchWorkItem?
    private var lastOrigin: NSPoint?
    private var lastOverflow = false
    private var fadeTimer: Timer?
    private var visibilityTarget: CGFloat = 0
    private var pointerMonitor: Any?

    var readingScroller: ReadingScroller? { verticalScroller as? ReadingScroller }
    var hasVerticalOverflow: Bool {
        guard let documentView, contentView.bounds.height > 0 else { return false }
        return documentView.frame.height > contentView.bounds.height + 0.5
    }
    var proximityRect: NSRect {
        let width = min(bounds.width / 3, 120)
        return NSRect(x: bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A stable transparent gutter keeps text from reflowing on reveal. AppKit
        // still owns the clip view, wheel momentum, knob tracking and AX actions.
        scrollerStyle = .legacy
        autohidesScrollers = false
        verticalScroller = ReadingScroller(frame: .zero)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        borderType = .noBorder
        drawsBackground = false
        readingScroller?.owner = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        hideWork?.cancel(); fadeTimer?.invalidate()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        guard let window else { updateProximity(at: nil); return }
        window.acceptsMouseMovedEvents = true
        // NSScrollView/NSTextView also own tracking areas. Observe the local
        // pointer stream without consuming it, including instant cursor moves
        // followed by a click and movement over nested native controls.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel]) { [weak self] event in
            guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
            self.updateProximity(at: self.convert(event.locationInWindow, from: nil))
            self.readingScroller?.updateHover(at: self.readingScroller?.convert(event.locationInWindow, from: nil))
            return event
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let proximityArea { removeTrackingArea(proximityArea) }
        let area = NSTrackingArea(rect: proximityRect.intersection(visibleRect),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); proximityArea = area
        if let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
            updateProximity(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateProximity(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // An exit from AppKit's own inner tracking area is not necessarily an
        // exit from our wider proximity region.
        updateProximity(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateProximity(at: convert(event.locationInWindow, from: nil))
    }

    func updateProximity(at point: NSPoint?) {
        let near = point.map { proximityRect.contains($0) } ?? false
        guard near != pointerIsNear else { return }
        pointerIsNear = near
        if near { revealIndicator() } else { scheduleHide() }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        guard clipView === contentView, readingScroller != nil else { return }
        let origin = clipView.bounds.origin
        let moved = lastOrigin.map { abs($0.y - origin.y) > 0.1 } ?? false
        lastOrigin = origin
        let overflow = hasVerticalOverflow
        if !overflow {
            hideWork?.cancel(); setVisibility(0, animated: false)
        } else if moved || (!lastOverflow && pointerIsNear) {
            revealIndicator()
        }
        lastOverflow = overflow
        readingScroller?.needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        revealIndicator()
    }

    func setIndicatorDragging(_ dragging: Bool) {
        isDraggingIndicator = dragging
        if dragging { revealIndicator() } else { scheduleHide() }
        readingScroller?.needsDisplay = true
    }

    func revealIndicator() {
        guard hasVerticalOverflow else { return }
        hideWork?.cancel(); hideWork = nil
        setVisibility(1, animated: true)
        if !pointerIsNear && !isDraggingIndicator { scheduleHide() }
    }

    private func scheduleHide() {
        hideWork?.cancel(); hideWork = nil
        guard !pointerIsNear && !isDraggingIndicator else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerIsNear, !self.isDraggingIndicator else { return }
            self.setVisibility(0, animated: true)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func setVisibility(_ value: CGFloat, animated: Bool) {
        guard let scroller = readingScroller else { return }
        guard value != visibilityTarget || (!animated && scroller.revealAmount != value) else { return }
        visibilityTarget = value
        fadeTimer?.invalidate(); fadeTimer = nil
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            scroller.revealAmount = value; return
        }
        let start = Date.timeIntervalSinceReferenceDate, initial = scroller.revealAmount
        let duration = value > initial ? 0.14 : 0.20
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self, weak scroller] timer in
            guard let self, let scroller else { timer.invalidate(); return }
            let t = min(1, (Date.timeIntervalSinceReferenceDate - start) / duration)
            scroller.revealAmount = initial + (value - initial) * CGFloat(t * t * (3 - 2 * t))
            if t >= 1 { timer.invalidate(); self.fadeTimer = nil }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

/// Paint only the knob, retaining NSScroller's native drag, page and accessibility
/// behavior. Its transparent 18pt gutter remains reserved even while invisible.
final class ReadingScroller: NSScroller {
    weak var owner: ReadingScrollView?
    var revealAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    private(set) var hovered = false
    private var hoverArea: NSTrackingArea?
    override var isOpaque: Bool { false }
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 18 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    func updateHover(at point: NSPoint?) {
        let inside = point.map { bounds.contains($0) } ?? false
        guard inside != hovered else { return }
        hovered = inside
        if inside { owner?.revealIndicator() }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        owner?.setIndicatorDragging(true)
        defer { owner?.setIndicatorDragging(false) }
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        guard owner?.hasVerticalOverflow == true, revealAmount > 0 else { return }
        let nativeKnob = rect(for: .knob)
        guard nativeKnob.height > 0 else { return }
        let emphasized = hovered || owner?.isDraggingIndicator == true
        let width: CGFloat = emphasized ? 8 : 6
        let knob = NSRect(x: bounds.midX - width / 2, y: nativeKnob.minY,
                          width: width, height: nativeKnob.height)
        let opacity = revealAmount * (emphasized ? 0.85 : 0.48)
        let color = PaperTheme.muted
        if PaperTheme.style == .books {
            color.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: knob, xRadius: width / 2, yRadius: width / 2).fill()
        } else {
            Self.paintPigment(in: knob, color: color, opacity: opacity)
        }
    }

    private static func paintPigment(in rect: NSRect, color: NSColor, opacity: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let radius = rect.width / 2
        let shape = NSBezierPath()
        shape.move(to: NSPoint(x: rect.midX, y: rect.minY))
        shape.curve(to: NSPoint(x: rect.maxX, y: rect.minY + radius),
                    controlPoint1: NSPoint(x: rect.maxX - 0.6, y: rect.minY),
                    controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + 0.8))
        for step in 1...16 {
            let t = CGFloat(step) / 16
            shape.line(to: NSPoint(x: rect.maxX - 0.14 * sin(t * .pi * 3),
                                  y: rect.minY + radius + t * max(0, rect.height - 2 * radius)))
        }
        shape.curve(to: NSPoint(x: rect.midX, y: rect.maxY),
                    controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - 0.8),
                    controlPoint2: NSPoint(x: rect.maxX - 0.6, y: rect.maxY))
        shape.curve(to: NSPoint(x: rect.minX, y: rect.maxY - radius),
                    controlPoint1: NSPoint(x: rect.minX + 0.7, y: rect.maxY),
                    controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - 0.9))
        for step in (0..<16).reversed() {
            let t = CGFloat(step) / 16
            shape.line(to: NSPoint(x: rect.minX + 0.12 * sin(t * .pi * 2),
                                  y: rect.minY + radius + t * max(0, rect.height - 2 * radius)))
        }
        shape.curve(to: NSPoint(x: rect.midX, y: rect.minY),
                    controlPoint1: NSPoint(x: rect.minX, y: rect.minY + 0.8),
                    controlPoint2: NSPoint(x: rect.minX + 0.8, y: rect.minY))
        shape.close()
        color.withAlphaComponent(opacity).setFill(); shape.fill(); shape.addClip()
        // Long faint deposits and fine paper gaps share the existing palette;
        // all marks are deterministic, so a dragged thumb never shimmers.
        color.withAlphaComponent(opacity * 0.18).setFill()
        NSRect(x: rect.minX + rect.width * 0.3, y: rect.minY, width: 1, height: rect.height).fill()
        var seed: UInt64 = 391
        for _ in 0..<Int(rect.width * rect.height / 4) {
            seed = seed &* 2862933555777941757 &+ 3037000493
            let x = CGFloat((seed >> 24) % 10000) / 10000 * rect.width
            seed = seed &* 2862933555777941757 &+ 3037000493
            let y = CGFloat((seed >> 24) % 10000) / 10000 * rect.height
            PaperTheme.paper.withAlphaComponent(opacity * 0.22).setFill()
            NSRect(x: rect.minX + x, y: rect.minY + y, width: 0.5, height: 0.9).fill()
        }
    }
}
