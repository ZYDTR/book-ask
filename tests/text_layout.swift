import AppKit

/// Reproduces the app's initially-unlaid-out scroll view, streamed text and resizing.
/// Runs offscreen. It does not read or operate any other application's UI.
@main
struct TextLayoutRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 710),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let content = window.contentView!
        let (scroll, view) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 350)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        let sample = "be liable to 表示很可能遭遇不良后果。作者把客户调研比作挖掘文物，提问方式影响真实反馈。 "
        let text = String(repeating: sample, count: 100) + "\nhttps://example.com/" + String(repeating: "unbroken", count: 80)
        var failures = [String]()
        for width in [610, 500, 1000, 1500, 500, 610] {
            window.setContentSize(NSSize(width: width, height: 710))
            content.layoutSubtreeIfNeeded()
            // Two growing updates exercise the actual streaming replacement path.
            for contentText in [String(text.prefix(300)), text] {
                view.string = contentText
                view.layoutManager?.ensureLayout(for: view.textContainer!)
                view.scrollToEndOfDocument(nil)
                let viewport = scroll.contentView.bounds.width
                if abs(view.frame.width - viewport) > 0.5 {
                    failures.append("width \(width): text width \(view.frame.width) exceeds viewport \(viewport)")
                }
                let target = NSRect(x: 180, y: 60, width: viewport, height: scroll.contentView.bounds.height)
                let clamped = scroll.contentView.constrainBoundsRect(target)
                if abs(clamped.origin.x) > 0.5 {
                    failures.append("width \(width): horizontal scrolling reaches x=\(clamped.origin.x)")
                }
                if let manager = view.layoutManager, let container = view.textContainer {
                    let used = manager.usedRect(for: container)
                    if used.maxX + view.textContainerInset.width * 2 > viewport + 0.5 {
                        failures.append("width \(width): text/URL extends beyond visible width")
                    }
                    if contentText == text, used.height <= scroll.contentView.bounds.height {
                        failures.append("width \(width): long content failed to wrap vertically")
                    }
                }
            }
        }
        guard failures.isEmpty else {
            for failure in failures { print("FAIL: \(failure)") }
            exit(1)
        }
        print("PASS: 6 resize steps, streaming Chinese/English/long URL, width containment, vertical overflow and horizontal scroll clamp")
    }
}
