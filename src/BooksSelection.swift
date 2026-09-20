import AppKit
import ApplicationServices

/// Reads selection attributes from Apple Books only. Never copies, types, or changes the book.
enum BooksSelection {
    static let bundleID = "com.apple.iBooksX"

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        // The app-element timeout is not inherited by remote WebKit children.
        AXUIElementSetMessagingTimeout(element, 0.08)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func text(_ element: AXUIElement) -> String? {
        if let text = attribute(element, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        // Some WebKit elements expose a text marker range instead of AXSelectedText.
        if let range = attribute(element, "AXSelectedTextMarkerRange") {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &result) == .success,
               let text = result as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    struct ReadReport {
        let text: String?
        let diagnostics: [String: Any]
    }

    static func evidence(_ node: AXUIElement, path: String, selected: String) -> [String: Any] {
        var pid: pid_t = 0
        AXUIElementGetPid(node, &pid)
        var result: [String: Any] = ["path": path, "pid": pid, "selectedText": selected,
            "role": attribute(node, kAXRoleAttribute) as? String ?? "missing",
            "identifier": attribute(node, kAXIdentifierAttribute) as? String ?? "",
            "nodeHash": String(CFHash(node))]
        if let window = element(attribute(node, kAXWindowAttribute)) {
            result["windowTitle"] = attribute(window, kAXTitleAttribute) as? String ?? ""
            result["fullScreen"] = attribute(window, "AXFullScreen") as? Bool ?? false
        }
        for name in ["AXSelectedTextRange", "AXVisibleCharacterRange"] {
            var raw: CFTypeRef?
            result[name + "Error"] = AXUIElementCopyAttributeValue(node, name as CFString, &raw).rawValue
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { continue }
            var range = CFRange()
            guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { continue }
            result[name] = ["location": range.location, "length": range.length]
            if name == "AXSelectedTextRange" {
                for parameter in ["AXStringForRange", "AXBoundsForRange"] {
                    var value: CFTypeRef?
                    result[parameter + "Error"] = AXUIElementCopyParameterizedAttributeValue(node, parameter as CFString, raw, &value).rawValue
                    if let text = value as? String { result[parameter] = String(text.prefix(6000)) }
                    else if let value, CFGetTypeID(value) == AXValueGetTypeID() {
                        var rect = CGRect.zero
                        if AXValueGetValue(value as! AXValue, .cgRect, &rect) { result[parameter] = NSStringFromRect(rect) }
                    }
                }
                if let value = attribute(node, kAXValueAttribute) as? String {
                    let string = value as NSString
                    result["valueUTF16Length"] = string.length
                    if range.location >= 0, range.length >= 0, range.location <= string.length,
                       range.length <= string.length - range.location {
                        result["valueAtSelectedRange"] = String(string.substring(with: NSRange(location: range.location, length: range.length)).prefix(6000))
                        let start = max(0, range.location - 70)
                        let end = min(string.length, range.location + range.length + 70)
                        result["nearbyText"] = String(string.substring(with: NSRange(location: start, length: end - start)).prefix(6200))
                    } else { result["valueRangeOutOfBounds"] = true }
                }
            }
        }
        for name in [kAXPositionAttribute, kAXSizeAttribute] {
            if let value = attribute(node, name), CFGetTypeID(value) == AXValueGetTypeID() {
                if name == kAXPositionAttribute {
                    var point = CGPoint.zero
                    if AXValueGetValue(value as! AXValue, .cgPoint, &point) { result[name] = NSStringFromPoint(point) }
                } else {
                    var size = CGSize.zero
                    if AXValueGetValue(value as! AXValue, .cgSize, &size) { result[name] = NSStringFromSize(size) }
                }
            }
        }
        if let marker = attribute(node, "AXSelectedTextMarkerRange") {
            var value: CFTypeRef?
            result["markerStringError"] = AXUIElementCopyParameterizedAttributeValue(node, "AXStringForTextMarkerRange" as CFString, marker, &value).rawValue
            if let text = value as? String { result["markerString"] = String(text.prefix(6000)) }
        }
        return result
    }

    static func inspect(pid: pid_t, preferred: AXUIElement? = nil, point: CGPoint? = nil, diagnostics: Bool = false) -> ReadReport {
        let started = Date()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.18)
        var rootErrors = [String: Int32]()
        func root(_ name: String) -> AXUIElement? {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(app, name as CFString, &value)
            rootErrors[name] = error.rawValue
            return element(value)
        }
        let focused = root(kAXFocusedUIElementAttribute)
        var hit: AXUIElement?
        if let point {
            rootErrors["hitTest"] = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit).rawValue
            if let node = hit {
                var owner: pid_t = 0
                AXUIElementGetPid(node, &owner)
                rootErrors["hitTestPID"] = owner
                // A point lookup must not bring another app into the Books tree.
                if owner != pid { hit = nil }
            }
        }
        let focusedWindow = root(kAXFocusedWindowAttribute)
        let mainWindow = root(kAXMainWindowAttribute)
        let window = focusedWindow ?? mainWindow
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let role = focused.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? "missing"
        let windowTitle = window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? "missing"
        var visited = 0
        var textNodes = [[String: Any]]()
        var queue: [(AXUIElement, String)] = [(preferred, "event"), (focused, "focused"), (focusedWindow, "focusedWindow"), (mainWindow, "mainWindow"), (hit, "hitTest")].compactMap { node, path in node.map { ($0, path) } }
        queue += windows.enumerated().map { ($0.element, "windows[\($0.offset)]") }
        var seen = [AXUIElement]()
        var selectedSource = [String: Any]()
        let windowInfo = windows.map { item -> [String: Any] in
            var value: [String: Any] = [
                "title": attribute(item, kAXTitleAttribute) as? String ?? "",
                "fullScreen": attribute(item, "AXFullScreen") as? Bool ?? false,
                "isFocusedRoot": focusedWindow.map { CFEqual(item, $0) } ?? false,
                "isMainRoot": mainWindow.map { CFEqual(item, $0) } ?? false
            ]
            if diagnostics {
                var attributes: CFArray?
                if AXUIElementCopyAttributeNames(item, &attributes) == .success {
                    value["attributes"] = attributes as? [String] ?? []
                }
            }
            return value
        }
        func finish(_ text: String?, _ reason: String) -> ReadReport {
            ReadReport(text: text, diagnostics: [
                "reason": reason, "visited": visited, "queued": queue.count,
                "focusedRole": role, "windowTitle": windowTitle,
                "rootErrors": rootErrors, "textNodes": textNodes, "windows": windowInfo,
                "selectedSource": selectedSource, "booksPID": pid,
                "focusedWindowFullScreen": window.flatMap { attribute($0, "AXFullScreen") as? Bool } ?? false,
                "elapsedMS": Int(Date().timeIntervalSince(started) * 1000)
            ])
        }
        if let preferred, let result = text(preferred) {
            selectedSource = evidence(preferred, path: "event", selected: result)
            return finish(result, "event_selection")
        }
        if let focused, let result = text(focused) {
            selectedSource = evidence(focused, path: "focused", selected: result)
            return finish(result, "focused_selection")
        }
        // Books focuses a container, so inspect its descendants and then its window.
        let deadline = Date().addingTimeInterval(0.65)
        while !queue.isEmpty, visited < 160, Date() < deadline {
            let (node, path) = queue.removeFirst()
            if seen.contains(where: { CFEqual($0, node) }) { continue }
            seen.append(node)
            AXUIElementSetMessagingTimeout(node, 0.08)
            visited += 1
            if let result = text(node) {
                selectedSource = evidence(node, path: path, selected: result)
                return finish(result, "descendant_selection")
            }
            if diagnostics, let role = attribute(node, kAXRoleAttribute) as? String,
               ["AXWebArea", "AXStaticText", "AXTextArea"].contains(role) {
                var description: [String: Any] = ["role": role]
                if role == "AXWebArea" {
                    var names: CFArray?
                    if AXUIElementCopyAttributeNames(node, &names) == .success {
                        description["attributes"] = names as? [String] ?? []
                    }
                }
                for name in ["AXSelectedText", "AXSelectedTextRange", "AXSelectedTextMarkerRange"] {
                    var value: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(node, name as CFString, &value)
                    description[name + "Error"] = error.rawValue
                    if let value {
                        description[name + "Type"] = CFCopyTypeIDDescription(CFGetTypeID(value)) as String
                        if name == "AXSelectedText", let text = value as? String { description["selectedLength"] = text.count }
                        if CFGetTypeID(value) == AXValueGetTypeID() {
                            var range = CFRange()
                            if AXValueGetValue(value as! AXValue, .cfRange, &range) {
                                description["rangeLocation"] = range.location
                                description["rangeLength"] = range.length
                            }
                        }
                    }
                }
                textNodes.append(description)
            }
            var descendants = [(AXUIElement, String)]()
            for name in ["AXChildrenInNavigationOrder", kAXChildrenAttribute, kAXLinkedUIElementsAttribute] {
                if let children = attribute(node, name) as? [AXUIElement] {
                    descendants.append(contentsOf: children.prefix(80).enumerated().map { ($0.element, path + "/" + name + "[\($0.offset)]") })
                }
            }
            // Finish the reading subtree before walking the unrelated library window.
            queue.insert(contentsOf: descendants, at: 0)
        }
        return finish(nil, queue.isEmpty ? "no_selection" : (visited >= 160 ? "node_limit" : "time_limit"))
    }
}
