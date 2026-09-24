import Foundation
import CryptoKit

struct ReadingPageSnapshot: Sendable {
    var bookTitle: String
    var visibleText: String
    var selectedRange: NSRange?
}

struct LocalContextResult: Sendable {
    var book: String
    var text: String
    var status: String
    var chapter: String = ""
    var indexReused = false
    var match: ContextMatch {
        ContextMatch(paragraphs: text.isEmpty ? [] : [BookParagraph(id: "local:" + chapter, chapter: chapter, text: text)], status: status)
    }
}

struct IndexedSection: Codable, Sendable {
    var title: String
    var text: String
}

struct LocalBookIndex: Codable, Sendable {
    let version: Int
    let sections: [IndexedSection]

    static let wordPattern = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’\\-][\\p{L}\\p{N}]+)*")
    static func words(_ value: String) -> [NSTextCheckingResult] {
        wordPattern.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length))
    }
    static func occurrences(_ needle: String, in text: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let hay = text as NSString; var result = [NSRange](); var offset = 0
        while offset < hay.length {
            let hit = hay.range(of: needle, range: NSRange(location: offset, length: hay.length - offset))
            if hit.location == NSNotFound { break }
            result.append(hit); offset = hit.location + max(1, hit.length)
        }
        return result
    }
    func locate(selection: String, page: ReadingPageSnapshot) -> LocalContextResult {
        let selected = ReadingContext.normalize(selection)
        let visible = ReadingContext.normalize(page.visibleText)
        func missing(_ reason: String) -> LocalContextResult { LocalContextResult(book: page.bookTitle, text: "", status: reason + " · 仅依据选中文字") }
        // The actual page/paragraph is required, even if the word is unique in the whole book.
        guard Self.words(visible).count >= 8, !selected.isEmpty else { return missing("无法定位当前书页") }
        var hits = [(Int, NSRange)]()
        for (i, section) in sections.enumerated() {
            hits += Self.occurrences(visible, in: section.text).map { (i, $0) }
        }
        guard hits.count == 1, let hit = hits.first else { return missing("当前书页无法唯一匹配") }
        let selectedHits = Self.occurrences(selected, in: visible)
        var relative: NSRange?
        if let raw = page.selectedRange, raw.location >= 0, raw.length > 0,
           NSMaxRange(raw) <= (page.visibleText as NSString).length {
            let original = page.visibleText as NSString
            if ReadingContext.normalize(original.substring(with: raw)) == selected {
                let prefix = ReadingContext.normalize(original.substring(to: raw.location))
                // Normalization trims a boundary space; choose only the range at that exact prefix.
                relative = selectedHits.first { $0.location == (prefix as NSString).length || $0.location == (prefix as NSString).length + 1 }
            }
        }
        if relative == nil && selectedHits.count == 1 { relative = selectedHits[0] }
        guard let relative else { return missing("同页有多处相同表达") }
        let section = sections[hit.0]
        let range = NSRange(location: hit.1.location + relative.location, length: relative.length)
        let tokens = Self.words(section.text)
        let before = tokens.filter { NSMaxRange($0.range) <= range.location }.suffix(200)
        let after = tokens.filter { $0.range.location >= NSMaxRange(range) }.prefix(200)
        let start = before.first?.range.location ?? range.location
        let end = after.last.map { NSMaxRange($0.range) } ?? NSMaxRange(range)
        let context = (section.text as NSString).substring(with: NSRange(location: start, length: end - start))
        return LocalContextResult(book: page.bookTitle, text: context,
            status: "当前语境 · 前\(before.count)词 / 后\(after.count)词" + (section.title == "章节未知" ? " · 章节未知" : ""), chapter: section.title)
    }
}

private enum EPUBFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// XML parsing and unpacking stay on the index actor, never on the main thread.
enum NativeEPUB {
    private static func run(_ args: [String]) throws -> Data {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); task.arguments = args
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try task.run(); let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw EPUBFailure.invalid("EPUB无法解包") }
        return bytes
    }
    static func build(at url: URL) throws -> LocalBookIndex {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw EPUBFailure.invalid("本地图书文件尚不可读") }
        if directory.boolValue { return try parse(root: url) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("BookAsk-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temp) }
        let listing = String(decoding: try run(["-Z1", url.path]), as: UTF8.self).split(separator: "\n")
        guard listing.count < 20000, listing.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else { throw EPUBFailure.invalid("EPUB路径无效") }
        _ = try run(["-q", url.path, "-d", temp.path])
        return try parse(root: temp)
    }
    private static func parse(root: URL) throws -> LocalBookIndex {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        func safe(_ url: URL) throws -> URL {
            let file = url.resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else { throw EPUBFailure.invalid("图书资源路径无效") }
            return file
        }
        func document(_ url: URL, html: Bool = false) throws -> XMLDocument {
            let data = try Data(contentsOf: safe(url))
            guard data.count <= 20_000_000 else { throw EPUBFailure.invalid("图书单个正文资源过大") }
            return try XMLDocument(data: data, options: html ? [.documentTidyHTML, .nodeLoadExternalEntitiesNever] : [.nodeLoadExternalEntitiesNever])
        }
        func nodes(_ node: XMLNode, _ name: String) -> [XMLNode] { (try? node.nodes(forXPath: ".//*[local-name()='\(name)']")) ?? [] }
        func attr(_ node: XMLNode, _ name: String) -> String { (node as? XMLElement)?.attribute(forName: name)?.stringValue ?? "" }
        func target(_ href: String, base: URL) throws -> (URL, String) {
            guard let resolved = URL(string: href, relativeTo: base)?.absoluteURL,
                  var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else { throw EPUBFailure.invalid("目录链接无效") }
            let fragment = parts.fragment ?? ""; parts.fragment = nil; parts.query = nil
            guard let url = parts.url else { throw EPUBFailure.invalid("目录链接无效") }
            return (try safe(url), fragment)
        }
        let container = try document(root.appendingPathComponent("META-INF/container.xml"))
        guard let packagePath = nodes(container, "rootfile").first.map({ attr($0, "full-path") }), !packagePath.isEmpty else { throw EPUBFailure.invalid("缺少EPUB正文目录") }
        let packageURL = root.appendingPathComponent(packagePath)
        let package = try document(packageURL)
        let items = nodes(package, "item")
        var manifest = [String: XMLNode]()
        for item in items { manifest[attr(item, "id")] = item }
        let spine = nodes(package, "itemref").filter { attr($0, "linear") != "no" }
        var encrypted = Set<String>()
        let encryptionURL = root.appendingPathComponent("META-INF/encryption.xml")
        if FileManager.default.fileExists(atPath: encryptionURL.path) {
            let encryption = try document(encryptionURL)
            for node in nodes(encryption, "CipherReference") { encrypted.insert(try target(attr(node, "URI"), base: root.appendingPathComponent("dummy" )).0.path) }
        }
        var full = ""; var anchors = [String: Int](); var fileStarts = [(String, Int)]()
        let blocks: Set<String> = ["p", "div", "section", "article", "h1", "h2", "h3", "h4", "li", "br", "tr", "blockquote"]
        for ref in spine {
            guard let item = manifest[attr(ref, "idref")] else { throw EPUBFailure.invalid("图书缺少正文文件") }
            let file = try target(attr(item, "href"), base: packageURL).0
            guard !encrypted.contains(file.path) else { throw EPUBFailure.invalid("图书正文受保护") }
            let doc = try document(file, html: true)
            guard let body = nodes(doc, "body").first else { throw EPUBFailure.invalid("图书正文不可读") }
            full += "\n"; anchors[file.path + "#"] = (full as NSString).length
            fileStarts.append((file.lastPathComponent, (full as NSString).length))
            func walk(_ node: XMLNode) {
                if node.kind == .text { full += node.stringValue ?? ""; return }
                let name = node.localName ?? node.name ?? ""
                if ["script", "style", "head"].contains(name) { return }
                if blocks.contains(name) { full += "\n" }
                let id = attr(node, "id")
                if !id.isEmpty { anchors[file.path + "#" + id] = (full as NSString).length }
                for child in node.children ?? [] { walk(child) }
                if blocks.contains(name) { full += "\n" }
            }
            walk(body)
            guard full.utf16.count <= 15_000_000 else { throw EPUBFailure.invalid("整本图书正文过大") }
        }
        var boundaries = [(String, Int)](); var missingAnchor = false
        if let nav = items.first(where: { attr($0, "properties").split(separator: " ").contains("nav") }) {
            let navURL = try target(attr(nav, "href"), base: packageURL).0
            let doc = try document(navURL, html: true)
            if let toc = nodes(doc, "nav").first(where: { attr($0, "epub:type").contains("toc") || attr($0, "type").contains("toc") }) {
                for link in nodes(toc, "a") {
                    let (url, fragment) = try target(attr(link, "href"), base: navURL)
                    if let offset = anchors[url.path + "#" + fragment] { boundaries.append((link.stringValue ?? "", offset)) } else { missingAnchor = true }
                }
            }
        }
        if boundaries.isEmpty, let ncx = items.first(where: { attr($0, "media-type") == "application/x-dtbncx+xml" }) {
            let ncxURL = try target(attr(ncx, "href"), base: packageURL).0
            let doc = try document(ncxURL)
            for point in nodes(doc, "navPoint") {
                if let content = nodes(point, "content").first {
                    let (url, fragment) = try target(attr(content, "src"), base: ncxURL)
                    if let offset = anchors[url.path + "#" + fragment] { boundaries.append((nodes(point, "text").first?.stringValue ?? "", offset)) } else { missingAnchor = true }
                }
            }
        }
        if missingAnchor { boundaries = [] }
        boundaries.sort { $0.1 < $1.1 }
        var seen = Set<Int>(); boundaries = boundaries.filter { seen.insert($0.1).inserted }
        if boundaries.isEmpty { boundaries = [("章节未知", 0)] }
        else if boundaries[0].1 > 0 { boundaries.insert(("卷首", 0), at: 0) }
        let raw = full as NSString
        let sections = boundaries.enumerated().compactMap { i, boundary -> IndexedSection? in
            let end = i + 1 < boundaries.count ? boundaries[i + 1].1 : raw.length
            guard end > boundary.1 else { return nil }
            let text = ReadingContext.normalize(raw.substring(with: NSRange(location: boundary.1, length: end - boundary.1)))
            return text.isEmpty ? nil : IndexedSection(title: boundary.0, text: text)
        }
        guard !sections.isEmpty else { throw EPUBFailure.invalid("图书没有可读正文") }
        return LocalBookIndex(version: 1, sections: sections)
    }
}

actor LocalBookContext {
    static let shared = LocalBookContext()
    let home: URL
    let indexDirectory: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, indexDirectory: URL? = nil) {
        self.home = home
        self.indexDirectory = indexDirectory ?? home.appendingPathComponent("Library/Application Support/BookAsk/Indexes")
    }
    func resolve(selection: String, page: ReadingPageSnapshot?) -> LocalContextResult {
        guard let page, !page.bookTitle.isEmpty else { return LocalContextResult(book: "图书", text: "", status: "无法识别当前书 · 仅依据选中文字") }
        do {
            let catalogURL = home.appendingPathComponent("Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books/Books.plist")
            let raw = try PropertyListSerialization.propertyList(from: Data(contentsOf: catalogURL), format: nil)
            let rows = (raw as? [String: Any])?["Books"] as? [[String: Any]] ?? []
            let matching = rows.filter { ReadingContext.normalize($0["itemName"] as? String ?? "") == ReadingContext.normalize(page.bookTitle) }
            let paths = Set(matching.compactMap { $0["path"] as? String })
            guard paths.count == 1, let path = paths.first else { throw EPUBFailure.invalid("当前书的本地文件无法唯一识别") }
            let url = URL(fileURLWithPath: path)
            let fingerprint = try sourceSignature(url)
            let stored = indexDirectory.appendingPathComponent(fingerprint + ".json")
            let index: LocalBookIndex; let reused: Bool
            if let data = try? Data(contentsOf: stored), let cached = try? JSONDecoder().decode(LocalBookIndex.self, from: data), cached.version == 1 {
                index = cached; reused = true
            } else {
                index = try NativeEPUB.build(at: url); reused = false
                try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(index).write(to: stored, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stored.path)
            }
            var result = index.locate(selection: selection, page: page); result.indexReused = reused; return result
        } catch { return LocalContextResult(book: page.bookTitle, text: "", status: (error is EPUBFailure ? error.localizedDescription : "本地图书暂不可读") + " · 仅依据选中文字") }
    }
    private func sourceSignature(_ url: URL) throws -> String {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey]
        let first = try url.resourceValues(forKeys: keys)
        var lines = ["native-epub-v1", url.path]
        if first.isDirectory == true {
            guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { throw EPUBFailure.invalid("本地图书暂不可读") }
            for case let file as URL in files {
                let values = try file.resourceValues(forKeys: keys)
                if values.isRegularFile == true { lines.append("\(file.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)") }
            }
        } else { lines.append("\(first.fileSize ?? 0)|\(first.contentModificationDate?.timeIntervalSince1970 ?? 0)") }
        return SHA256.hash(data: Data(lines.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
