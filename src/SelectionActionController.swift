import AppKit
import ApplicationServices

struct SelectionActionContext {
    var booksPID: pid_t?
    var trusted: Bool
    var mouseButtons: Int

    @MainActor static func current() -> Self {
        let front = NSWorkspace.shared.frontmostApplication
        return Self(booksPID: front?.bundleIdentifier == BooksSelection.bundleID ? front?.processIdentifier : nil,
                    trusted: AXIsProcessTrusted(), mouseButtons: Int(NSEvent.pressedMouseButtons))
    }
}

/// Keep Books as the active/key application so clicking the offer leaves its
/// selection intact for the subsequent protected copy transaction.
final class SelectionActionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A native button keeps the selection-confirmation action and accessibility
/// semantics; the small badge shares the reader's current material and ink.
final class SelectionActionButton: NSButton {
    static let diameter: CGFloat = 36

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        title = "AI"
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel("问 AI")
        toolTip = "用选中的文字打开读书提问"
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: Self.diameter, height: Self.diameter) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        PaperTheme.paper.setFill(); bounds.fill()
        if PaperTheme.style == .paper {
            PaperTheme.wash(in: bounds, color: PaperTheme.sage, opacity: 0.28)
        }
        if isHighlighted {
            PaperTheme.ink.withAlphaComponent(0.10).setFill(); bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        PaperTheme.muted.withAlphaComponent(0.42).setStroke()
        circle.lineWidth = 0.75; circle.stroke()
        let font = PaperTheme.style == .books ? PaperTheme.systemSerif(13) : NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: PaperTheme.ink]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: focusRingMaskBounds).fill() }
}

@MainActor final class SelectionActionController: NSObject {
    let panel: SelectionActionPanel
    let button: SelectionActionButton
    var onConfirm: (() -> Void)?
    var onCancel: ((String) -> Void)?
    private var localMonitor: Any?

    override init() {
        panel = SelectionActionPanel(contentRect: NSRect(x: 0, y: 0, width: SelectionActionButton.diameter, height: SelectionActionButton.diameter),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        button = SelectionActionButton()
        super.init()
        panel.title = "划词提问"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) {
            panel.collectionBehavior.insert(.canJoinAllApplications)
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        button.target = self
        button.action = #selector(confirm)
        button.toolTip = "用选中的文字打开读书提问"
        button.frame = NSRect(origin: .zero, size: panel.frame.size)
        button.autoresizingMask = [.width, .height]
        panel.contentView = button
    }

    func startMonitoring() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A left click belongs to our native button tracking. Other
                // local input invalidates the offer without swallowing the input.
                if event.window !== self.panel || event.type != .leftMouseDown {
                    self.onCancel?("local_input")
                }
            }
            return event
        }
    }

    func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        hide()
    }

    static func frame(near point: NSPoint, in visibleFrame: NSRect, size: NSSize) -> NSRect {
        let safe = visibleFrame.insetBy(dx: 6, dy: 6)
        // Prefer below/right; flip above/left before clamping at display edges.
        let x = point.x + 12 + size.width <= safe.maxX ? point.x + 12 : point.x - 12 - size.width
        let y = point.y - 12 - size.height >= safe.minY ? point.y - 12 - size.height : point.y + 12
        return NSRect(x: max(safe.minX, min(x, safe.maxX - size.width)),
                      y: max(safe.minY, min(y, safe.maxY - size.height)), width: size.width, height: size.height)
    }

    @discardableResult func show(near point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        PaperTheme.apply(ReadingPreferences.appearance(), to: panel)
        panel.setFrame(Self.frame(near: point, in: screen.visibleFrame, size: panel.frame.size), display: false)
        button.needsDisplay = true
        panel.orderFrontRegardless()
        return true
    }

    func contains(_ point: NSPoint) -> Bool { panel.isVisible && panel.frame.contains(point) }
    func hide() { panel.orderOut(nil) }
    @objc private func confirm() { onConfirm?() }
}
