import AppKit

/// Original, deterministic vector textures. No external image/font resources.
enum PaperTheme {
    private static let paperColors = palette(books: false)
    private static let bookColors = palette(books: true)
    static var style: ReadingStyle { ReadingPreferences.style() }
    private static var colors: [String: NSColor] { style == .books ? bookColors : paperColors }
    static var paper: NSColor { colors["paper"]! }
    static var ink: NSColor { colors["ink"]! }
    static var muted: NSColor { colors["muted"]! }
    static var line: NSColor { colors["line"]! }
    static var ochre: NSColor { colors["ochre"]! }
    static var blue: NSColor { colors["blue"]! }
    static var sage: NSColor { colors["sage"]! }
    static var coral: NSColor { colors["coral"]! }
    static var input: NSColor { colors["input"]! }
    static var buttonInk: NSColor { colors["buttonInk"]! }

    private static func palette(books: Bool) -> [String: NSColor] {
        let values: [(String, Int, Int)] = books ? [
            ("paper", 0xFFFFFF, 0x000000), ("ink", 0x111111, 0xFFFFFF),
            ("muted", 0x777777, 0x999999), ("line", 0xDDDDDD, 0x303030),
            ("ochre", 0xD7AD38, 0xD7AD38), ("blue", 0x72AACF, 0x72AACF),
            ("sage", 0xDDDDDD, 0xDDDDDD), ("coral", 0xA46438, 0xCFA37F),
            ("input", 0xFFFFFF, 0x000000), ("buttonInk", 0x111111, 0x111111)
        ] : [
            ("paper", 0xFAF8F2, 0x29312C), ("ink", 0x303831, 0xE9E6DD),
            ("muted", 0x73796E, 0xA1AAA0), ("line", 0xDCDDD1, 0x485246),
            ("ochre", 0xE7B857, 0xD6AC60), ("blue", 0x8DBCD1, 0x94B7C4),
            ("sage", 0xA9BC9A, 0xA2B58D), ("coral", 0xAD5949, 0xCEA185),
            ("input", 0xFDFCF9, 0x2D352D), ("buttonInk", 0xFFFFFF, 0x242B24)
        ]
        return Dictionary(uniqueKeysWithValues: values.map { name, light, dark in
            (name, adaptive((books ? "Books." : "Paper.") + name, light: light, dark: dark))
        })
    }

    static func isDark(_ appearance: NSAppearance = .currentDrawing()) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func adaptive(_ name: String, light: Int, dark: Int) -> NSColor {
        NSColor(name: NSColor.Name("BookAsk." + name)) { appearance in
            color(isDark(appearance) ? dark : light)
        }
    }

    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func systemSerif(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            .flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    static func serif(_ size: CGFloat) -> NSFont {
        style == .books ? systemSerif(size) : NSFont(name: "Charter-Roman", size: size) ?? systemSerif(size)
    }

    static func readingFont(_ size: CGFloat) -> NSFont {
        style == .books ? systemSerif(size) : .systemFont(ofSize: size)
    }

    static let questionRole = NSAttributedString.Key("BookAsk.questionRole")

    static func paragraph(spacing: CGFloat = 4) -> NSParagraphStyle {
        let result = NSMutableParagraphStyle()
        result.lineBreakMode = .byWordWrapping
        result.lineSpacing = spacing
        result.paragraphSpacing = 2
        return result
    }

    static func readingParagraph(_ size: CGFloat) -> NSParagraphStyle {
        guard style == .books else { return paragraph() }
        let result = NSMutableParagraphStyle()
        result.lineBreakMode = .byWordWrapping
        result.minimumLineHeight = size * 1.28
        result.maximumLineHeight = size * 1.28
        result.hyphenationFactor = 1
        result.paragraphSpacing = 2
        return result
    }

    /// An empty paragraph is a small reading pause, not another full text line.
    /// Preserve the actual answer string (including newlines) for selection/copy.
    static func compactParagraphBreaks(_ text: NSMutableAttributedString) {
        let gap = NSMutableParagraphStyle()
        gap.minimumLineHeight = 10; gap.maximumLineHeight = 10
        let pattern = try! NSRegularExpression(pattern: #"\n[ \t]*\n"#)
        for match in pattern.matches(in: text.string, range: NSRange(location: 0, length: text.length)) {
            text.addAttribute(.paragraphStyle, value: gap,
                range: NSRange(location: match.range.location + 1, length: match.range.length - 1))
        }
    }

    static func text(_ view: NSTextView, font: NSFont, inset: NSSize = NSSize(width: 8, height: 8)) {
        view.font = font
        view.textColor = ink
        view.insertionPointColor = coral
        view.selectedTextAttributes = [.backgroundColor: blue.withAlphaComponent(0.35), .foregroundColor: ink]
        view.defaultParagraphStyle = paragraph()
        view.textContainerInset = inset
        view.textContainer?.containerSize.width = max(0, view.bounds.width - inset.width * 2)
        view.typingAttributes = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph()]
    }

    static func window(_ window: NSWindow) {
        apply(ReadingPreferences.appearance(), to: window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
    }

    /// Dynamic colors stay in attributed text; switching does not rebuild a
    /// conversation, reload history, change focus or discard the user's draft.
    static func apply(_ choice: ReadingAppearance, to window: NSWindow) {
        switch choice {
        case .system: window.appearance = nil
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        }
        func invalidate(_ view: NSView) {
            view.needsDisplay = true
            if let text = view as? NSTextView {
                text.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: text.textStorage?.length ?? 0))
            }
            view.subviews.forEach(invalidate)
        }
        if let content = window.contentView { invalidate(content) }
    }

    /// Slightly uneven, mostly horizontal washes; fine marks stay inside the
    /// pigment shape. Text and focus indicators are drawn separately and crisply.
    static func wash(in rect: NSRect, color: NSColor, opacity: CGFloat = 0.22) {
        guard rect.width > 0 && rect.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let shape = NSBezierPath()
        let n = 28
        for i in 0...n {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n)
            let y = rect.minY + 1.0 + sin(CGFloat(i) * 0.81) * 0.35 + cos(CGFloat(i) * 1.73) * 0.2
            if i == 0 { shape.move(to: NSPoint(x: x, y: y)) }
            else { shape.line(to: NSPoint(x: x, y: y)) }
        }
        for i in (0...n).reversed() {
            shape.line(to: NSPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(n),
                                  y: rect.maxY - 1.0 + cos(CGFloat(i) * 0.93) * 0.4 + sin(CGFloat(i) * 2.07) * 0.2))
        }
        shape.close()
        color.withAlphaComponent(opacity).setFill(); shape.fill(); shape.addClip()
        // Wide, faint overlaps create direction and uneven coverage at normal size.
        for i in 0..<5 {
            let stripe = NSBezierPath()
            let y = rect.minY + rect.height * CGFloat(i + 1) / 6
            stripe.move(to: NSPoint(x: rect.minX - 5, y: y))
            stripe.curve(to: NSPoint(x: rect.maxX + 3, y: y + 2),
                         controlPoint1: NSPoint(x: rect.midX * 0.8, y: y + 5),
                         controlPoint2: NSPoint(x: rect.midX * 1.2, y: y - 4))
            stripe.lineWidth = rect.height * (i % 2 == 0 ? 0.18 : 0.09)
            color.withAlphaComponent(opacity * 0.21).setStroke(); stripe.stroke()
        }
        let dark = isDark()
        var seed: UInt64 = 173
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1
            return CGFloat((seed >> 32) % 10000) / 10000
        }
        for _ in 0..<Int(rect.width * rect.height / (dark ? 6 : 8)) {
            let x = rect.minX + random() * rect.width
            let y = rect.minY + random() * rect.height
            let size = 0.35 + random() * 1.05
            color.withAlphaComponent(opacity * (dark ? 0.25 + random() * 0.45 : 0.15 + random() * 0.42)).setFill()
            NSRect(x: x, y: y, width: size, height: size * 0.7).fill()
        }
        if dark {
            // The paper shows through small broken strokes in the pigment.
            for _ in 0..<Int(rect.width * rect.height / 90) {
                let mark = NSRect(x: rect.minX + random() * rect.width, y: rect.minY + random() * rect.height,
                                  width: 1 + random() * 5, height: 0.4 + random() * 0.5)
                paper.withAlphaComponent(0.23).setFill(); mark.fill()
            }
        }
        // A dry-brush edge, subordinate to the text rather than an outline box.
        color.withAlphaComponent(opacity * 0.6).setFill()
        NSRect(x: rect.minX + 1, y: rect.minY, width: 2.2, height: rect.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class PaperCanvas: NSView {
    var onLayout: ((CGFloat) -> Void)?
    override func layout() { super.layout(); onLayout?(bounds.width) }
    private var texture: NSImage?
    private var textureSize = NSSize.zero
    private var textureDark: Bool?
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y >= bounds.maxY - 62 { window?.performDrag(with: event) }
        else { super.mouseDown(with: event) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateShadow()
    }
    static func outline(_ rect: NSRect) -> NSBezierPath {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        if PaperTheme.style == .books { return NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20) }
        let tl: CGFloat = 20, tr: CGFloat = 46, br: CGFloat = 20, bl: CGFloat = 38
        let k: CGFloat = 0.55228475
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x + bl, y: y))
        p.line(to: NSPoint(x: x + w - br, y: y))
        p.curve(to: NSPoint(x: x + w, y: y + br), controlPoint1: NSPoint(x: x + w - br + k * br, y: y), controlPoint2: NSPoint(x: x + w, y: y + br - k * br))
        p.line(to: NSPoint(x: x + w, y: y + h - tr))
        p.curve(to: NSPoint(x: x + w - tr, y: y + h), controlPoint1: NSPoint(x: x + w, y: y + h - tr + k * tr), controlPoint2: NSPoint(x: x + w - tr + k * tr, y: y + h))
        p.line(to: NSPoint(x: x + tl, y: y + h))
        p.curve(to: NSPoint(x: x, y: y + h - tl), controlPoint1: NSPoint(x: x + tl - k * tl, y: y + h), controlPoint2: NSPoint(x: x, y: y + h - tl + k * tl))
        p.line(to: NSPoint(x: x, y: y + bl))
        p.curve(to: NSPoint(x: x + bl, y: y), controlPoint1: NSPoint(x: x, y: y + bl - k * bl), controlPoint2: NSPoint(x: x + bl - k * bl, y: y))
        p.close(); return p
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        texture = nil; textureDark = nil; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if PaperTheme.style == .books {
            PaperTheme.paper.setFill(); Self.outline(bounds).fill(); return
        }
        let dark = PaperTheme.isDark(effectiveAppearance)
        if texture == nil || textureSize != bounds.size || textureDark != dark {
            textureSize = bounds.size
            textureDark = dark
            let size = bounds.size
            // Resolve before caching so one theme's image cannot leak into another.
            var base = NSColor.clear, grain = NSColor.clear, pigment = NSColor.clear
            effectiveAppearance.performAsCurrentDrawingAppearance {
                base = PaperTheme.paper.usingColorSpace(.sRGB)!
                grain = PaperTheme.ink.usingColorSpace(.sRGB)!
                pigment = PaperTheme.sage.usingColorSpace(.sRGB)!
            }
            texture = NSImage(size: size, flipped: false) { rect in
                base.setFill(); rect.fill()
                // Sparse broad pigment deposits at the edges; the text axis
                // stays quiet. Grain/fibers are a separate, finer scale.
                for (top, width, height, opacity) in [(20.0, size.width * 1.2, 78.0, 0.04), (size.height * 0.58, size.width * 0.32, 105.0, 0.027), (size.height - 34, size.width, 66.0, 0.035)] {
                    for i in 0..<70 {
                        let t = CGFloat(i) / 70
                        let mark = NSBezierPath()
                        let y = size.height - top + (t - 0.5) * height
                        let x = -40 + sin(t * .pi) * 16
                        mark.move(to: NSPoint(x: x, y: y))
                        mark.curve(to: NSPoint(x: x + width, y: y + 5), controlPoint1: NSPoint(x: width * 0.25, y: y - 12), controlPoint2: NSPoint(x: width * 0.7, y: y + 10))
                        pigment.withAlphaComponent(CGFloat(opacity) * sin(t * CGFloat.pi)).setStroke()
                        mark.lineWidth = 0.5 + CGFloat(i % 3) * 0.13; mark.stroke()
                    }
                }
                var seed: UInt64 = 391
                for _ in 0..<Int(size.width * size.height / (dark ? 10 : 20)) {
                    seed = seed &* 2862933555777941757 &+ 3037000493
                    let x = CGFloat((seed >> 24) % 10000) / 10000 * size.width
                    seed = seed &* 2862933555777941757 &+ 3037000493
                    let y = CGFloat((seed >> 24) % 10000) / 10000 * size.height
                    grain.withAlphaComponent(dark ? 0.02 + CGFloat(seed % 17) / 1000 : 0.022).setFill()
                    NSRect(x: x, y: y, width: 0.6, height: 0.6).fill()
                    if dark && seed % 17 == 0 {
                        grain.withAlphaComponent(0.024).setFill()
                        NSRect(x: x, y: y, width: 3 + CGFloat(seed % 6), height: 0.45).fill()
                    }
                }
                return true
            }
        }
        NSGraphicsContext.saveGraphicsState()
        Self.outline(bounds).addClip()
        texture?.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class PigmentWell: NSView {
    var pigment: NSColor = PaperTheme.ochre
    var opacity: CGFloat = 0.21
    override func draw(_ dirtyRect: NSRect) {
        PaperTheme.wash(in: bounds.insetBy(dx: 2, dy: 2), color: pigment, opacity: opacity)
    }
}

final class PaperRule: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PaperTheme.line.withAlphaComponent(0.65).setFill(); bounds.fill()
    }
}

final class PaperInputWell: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PaperTheme.line.withAlphaComponent(0.7).setFill()
        NSRect(x: 0, y: bounds.maxY - 0.7, width: bounds.width, height: 0.7).fill()
    }
}

/// NSButton keeps native tracking, keyboard actions and AX semantics. Only its
/// drawing changes; controls are never painted into a non-interactive bitmap.
final class PaperButton: NSButton {
    enum Kind { case toggle, quiet, primary }
    let kind: Kind
    var symbolPointSize: CGFloat?
    var symbolOpacity: CGFloat = 0.7
    var circularHover = false
    var toolbarSizing = false { didSet { invalidateIntrinsicContentSize() } }
    var subduedUntilHover = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    var foregroundColorOverride: NSColor? { didSet { needsDisplay = true } }
    var symbol: String? { didSet { needsDisplay = true } }
    init(_ title: String, kind: Kind, symbol: String? = nil, target: AnyObject?, action: Selector?) {
        self.kind = kind; self.symbol = symbol
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        self.font = .systemFont(ofSize: 11, weight: .medium)
        isBordered = false
        setButtonType(kind == .toggle ? .switch : .momentaryPushIn)
        setAccessibilityLabel(title)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize {
        if toolbarSizing {
            let width = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)]).width
            return NSSize(width: max(28, ceil(width) + (kind == .toggle ? 18 : 10)), height: 30)
        }
        if title.isEmpty { return NSSize(width: 28, height: 28) }
        let textWidth = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11)]).width
        return NSSize(width: ceil(textWidth) + (kind == .toggle || symbol != nil ? 36 : 24), height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        let active = kind == .toggle && state == .on
        let rect = bounds.insetBy(dx: 1, dy: 2)
        if circularHover && (hovered || isHighlighted) {
            PaperTheme.blue.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        }
        if kind == .primary {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).addClip()
            PaperTheme.sage.withAlphaComponent(isHighlighted ? 0.65 : 0.88).setFill(); bounds.fill()
            if PaperTheme.style == .paper { PaperTheme.wash(in: bounds, color: PaperTheme.sage, opacity: 0.25) }
            NSGraphicsContext.restoreGraphicsState()
        } else if active {
            if isHighlighted { PaperTheme.wash(in: rect, color: PaperTheme.sage, opacity: 0.16) }
        } else if isHighlighted || (toolbarSizing && hovered) {
            PaperTheme.wash(in: rect, color: PaperTheme.blue, opacity: 0.2)
        }
        let focused = window?.firstResponder === self
        let base = subduedUntilHover && !hovered && !isHighlighted && !focused ? PaperTheme.muted : PaperTheme.ink
        let foreground = (foregroundColorOverride ?? (kind == .primary ? PaperTheme.buttonInk : base)).withAlphaComponent(isEnabled ? 1 : 0.35)
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 11), .foregroundColor: foreground]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let leading: CGFloat = kind == .toggle ? (toolbarSizing ? 18 : 25) : (symbol != nil && !title.isEmpty) ? 25 : (bounds.width - textSize.width) / 2
        (title as NSString).draw(at: NSPoint(x: leading, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
        if kind == .toggle {
            let box = NSRect(x: toolbarSizing ? 4 : 9, y: (bounds.height - 10) / 2, width: 10, height: 10)
            let outline = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            if active { PaperTheme.ink.withAlphaComponent(0.75).setFill(); outline.fill() }
            else { PaperTheme.muted.withAlphaComponent(0.55).setStroke(); outline.lineWidth = 1; outline.stroke() }
            if active {
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: box.minX + 2.2, y: box.midY))
                tick.line(to: NSPoint(x: box.minX + 4.2, y: isFlipped ? box.maxY - 2.8 : box.minY + 2.8))
                tick.line(to: NSPoint(x: box.maxX - 2, y: isFlipped ? box.minY + 2.6 : box.maxY - 2.6))
                PaperTheme.paper.setStroke(); tick.lineWidth = 1.1; tick.stroke()
            }
        } else if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [foreground])) {
            let iconSize: CGFloat = symbolPointSize ?? (toolbarSizing ? 15 : 12)
            let iconRect = NSRect(x: title.isEmpty ? (bounds.width - iconSize) / 2 : 8, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: symbolOpacity, respectFlipped: true, hints: nil)
        }
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill()
    }
}

final class PaperTableRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        PaperTheme.sage.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 8, yRadius: 8).fill()
    }
}
