import AppKit

/// Original, deterministic vector textures. No external image/font resources.
enum PaperTheme {
    static let paper = adaptive("paper", light: 0xFAF8F2, dark: 0x232923)
    static let ink = adaptive("ink", light: 0x303831, dark: 0xF0EBDD)
    static let muted = adaptive("muted", light: 0x73796E, dark: 0xADB2A5)
    static let line = adaptive("line", light: 0xDCDDD1, dark: 0x485246)
    static let ochre = adaptive("ochre", light: 0xE7B857, dark: 0xD6AC60)
    static let blue = adaptive("blue", light: 0x8DBCD1, dark: 0x94B7C4)
    static let sage = adaptive("sage", light: 0xA9BC9A, dark: 0xA2B58D)
    static let coral = adaptive("coral", light: 0xAD5949, dark: 0xCF957B)
    static let input = adaptive("input", light: 0xFDFCF9, dark: 0x2D352D)
    static let buttonInk = adaptive("buttonInk", light: 0xFFFFFF, dark: 0x242B24)

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

    static func serif(_ size: CGFloat) -> NSFont {
        NSFont(name: "NewYork-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
            ?? .systemFont(ofSize: size)
    }

    static func paragraph(spacing: CGFloat = 4) -> NSParagraphStyle {
        let result = NSMutableParagraphStyle()
        result.lineBreakMode = .byWordWrapping
        result.lineSpacing = spacing
        result.paragraphSpacing = 2
        return result
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
        window.backgroundColor = paper
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
    private var texture: NSImage?
    private var textureSize = NSSize.zero
    private var textureDark: Bool?
    override var isOpaque: Bool { true }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        texture = nil; textureDark = nil; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = PaperTheme.isDark(effectiveAppearance)
        if texture == nil || textureSize != bounds.size || textureDark != dark {
            textureSize = bounds.size
            textureDark = dark
            let size = bounds.size
            // Resolve before caching so one theme's image cannot leak into another.
            var base = NSColor.clear, grain = NSColor.clear
            effectiveAppearance.performAsCurrentDrawingAppearance {
                base = PaperTheme.paper.usingColorSpace(.sRGB)!
                grain = PaperTheme.ink.usingColorSpace(.sRGB)!
            }
            texture = NSImage(size: size, flipped: false) { rect in
                base.setFill(); rect.fill()
                var seed: UInt64 = 391
                for _ in 0..<Int(size.width * size.height / (dark ? 14 : 50)) {
                    seed = seed &* 2862933555777941757 &+ 3037000493
                    let x = CGFloat((seed >> 24) % 10000) / 10000 * size.width
                    seed = seed &* 2862933555777941757 &+ 3037000493
                    let y = CGFloat((seed >> 24) % 10000) / 10000 * size.height
                    grain.withAlphaComponent(dark ? 0.045 : 0.027).setFill()
                    NSRect(x: x, y: y, width: 0.6, height: 0.6).fill()
                    if dark && seed % 17 == 0 {
                        grain.withAlphaComponent(0.024).setFill()
                        NSRect(x: x, y: y, width: 3 + CGFloat(seed % 6), height: 0.45).fill()
                    }
                }
                return true
            }
        }
        texture?.draw(in: bounds)
    }
}

final class PigmentWell: NSView {
    var pigment: NSColor = PaperTheme.ochre
    var opacity: CGFloat = 0.21
    override func draw(_ dirtyRect: NSRect) {
        PaperTheme.wash(in: bounds.insetBy(dx: 2, dy: 2), color: pigment, opacity: opacity)
    }
}

final class PaperInputWell: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 13, yRadius: 13)
        PaperTheme.input.setFill(); path.fill()
        PaperTheme.line.setStroke(); path.lineWidth = 1; path.stroke()
    }
}

/// NSButton keeps native tracking, keyboard actions and AX semantics. Only its
/// drawing changes; controls are never painted into a non-interactive bitmap.
final class PaperButton: NSButton {
    enum Kind { case toggle, quiet, primary }
    let kind: Kind
    var symbol: String?
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
        let textWidth = (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11)]).width
        return NSSize(width: ceil(textWidth) + (kind == .toggle || symbol != nil ? 36 : 24), height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        let active = kind == .toggle && state == .on
        let rect = bounds.insetBy(dx: 1, dy: 2)
        if kind == .primary {
            PaperTheme.wash(in: rect, color: PaperTheme.coral, opacity: isHighlighted ? 0.85 : 0.98)
        } else if active {
            PaperTheme.wash(in: rect, color: PaperTheme.sage, opacity: isHighlighted ? 0.5 : 0.30)
        } else if isHighlighted {
            PaperTheme.wash(in: rect, color: PaperTheme.blue, opacity: 0.2)
        }
        let foreground = kind == .primary ? PaperTheme.buttonInk : PaperTheme.ink
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 11), .foregroundColor: foreground]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let leading: CGFloat = (kind == .toggle || symbol != nil) ? 25 : (bounds.width - textSize.width) / 2
        (title as NSString).draw(at: NSPoint(x: leading, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
        if kind == .toggle {
            let box = NSRect(x: 9, y: (bounds.height - 10) / 2, width: 10, height: 10)
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
            .withSymbolConfiguration(.init(paletteColors: [PaperTheme.ink])) {
            let iconRect = NSRect(x: 8, y: (bounds.height - 12) / 2, width: 12, height: 12)
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
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
        PaperTheme.wash(in: bounds.insetBy(dx: 3, dy: 2), color: PaperTheme.blue, opacity: 0.23)
    }
}
