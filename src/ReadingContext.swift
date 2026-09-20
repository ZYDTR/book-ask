import Foundation

struct BookParagraph: Codable {
    let id: String
    let chapter: String
    let text: String
}

struct ContextMatch {
    let paragraphs: [BookParagraph]
    let status: String
}

enum ReadingContext {
    static func cleanBooksClipboard(_ text: String) -> String {
        var result = text
        for marker in ["\n摘录来自", "\n摘錄自", "\nExcerpt From", "\n节选自"] {
            if let range = result.range(of: marker) { result = String(result[..<range.lowerBound]) }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if (result.hasPrefix("“") && result.hasSuffix("”")) || (result.hasPrefix("\"") && result.hasSuffix("\"")) {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func match(_ selection: String, in paragraphs: [BookParagraph]) -> ContextMatch {
        let needle = normalize(selection)
        guard needle.count >= 4 else { return ContextMatch(paragraphs: [], status: "选区较短，仅使用选中文字") }
        let hits = paragraphs.indices.filter { normalize(paragraphs[$0].text).contains(needle) }
        if hits.count == 1, let i = hits.first {
            let range = max(0, i - 1)...min(paragraphs.count - 1, i + 1)
            let nearby = range.map { paragraphs[$0] }.filter { $0.chapter == paragraphs[i].chapter }
            return ContextMatch(paragraphs: nearby, status: "已关联所在段落与前后文")
        }
        if hits.count > 1 { return ContextMatch(paragraphs: [], status: "书中有多处相同表达，仅使用选中文字") }
        // A user may select across a paragraph boundary.
        var cross: [[BookParagraph]] = []
        for i in paragraphs.indices where i + 1 < paragraphs.count {
            guard paragraphs[i].chapter == paragraphs[i + 1].chapter else { continue }
            let pair = [paragraphs[i], paragraphs[i + 1]]
            if normalize(pair.map(\.text).joined(separator: " ")).contains(needle) { cross.append(pair) }
        }
        if cross.count == 1 { return ContextMatch(paragraphs: cross[0], status: "已关联跨段选区") }
        return ContextMatch(paragraphs: [], status: "未唯一匹配本书，仅使用选中文字")
    }
}
