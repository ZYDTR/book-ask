import Foundation

struct WordbookExchange: Codable, Equatable, Sendable {
    let question: String
    let answer: String
    let automatic: Bool
}

/// One exact selected term, one definition, followed by explicit questions.
struct WordbookEntry: Codable, Sendable {
    var selection: String
    var book: String
    var latestTime: String
    var exchanges: [WordbookExchange]
    var id: String { selection }
    var hasAnswer: Bool { !exchanges.isEmpty }
    var status: String { hasAnswer ? "" : "尚未生成解释" }
    var conversation: [[String: String]] {
        exchanges.flatMap { [["role": "user", "content": $0.question], ["role": "assistant", "content": $0.answer]] }
    }
    var displayText: String {
        exchanges.enumerated().map { index, exchange in
            (index == 0 ? "" : "你：\(exchange.question)\n\n") + exchange.answer
        }.joined(separator: "\n\n")
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || ([selection, book] + exchanges.flatMap { [$0.question, $0.answer] })
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct LegacyVisit {
    let id: String
    let selection: String
    let book: String
    let time: String
    var exchanges: [WordbookExchange] = []
    var automatic = false
}

struct WordbookDocument: Codable {
    let version: Int
    let entries: [WordbookEntry]
}

enum WordbookStore {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BookAsk")
    }
    static var historyURL: URL { directory.appendingPathComponent("history.jsonl") }
    static var storeURL: URL { directory.appendingPathComponent("wordbook.json") }
    static func key(_ term: String) -> String { term.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Read-only compatibility entry for offline inspection. The running app uses
    /// WordbookLibrary so migration and writes share one serialized owner.
    static func load(fallbackBook: String) throws -> [WordbookEntry] {
        if FileManager.default.fileExists(atPath: storeURL.path) { return try decode(Data(contentsOf: storeURL)) }
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return parse(try Data(contentsOf: historyURL), fallbackBook: fallbackBook)
    }
    static func decode(_ data: Data) throws -> [WordbookEntry] {
        let document = try JSONDecoder().decode(WordbookDocument.self, from: data)
        guard document.version == 1,
              Set(document.entries.map(\.id)).count == document.entries.count,
              document.entries.allSatisfy({ !$0.id.isEmpty && $0.id == key($0.id) && $0.exchanges.allSatisfy { !key($0.answer).isEmpty } }) else {
            throw NSError(domain: "Wordbook", code: 1, userInfo: [NSLocalizedDescriptionKey: "词本格式不正确，已保留原文件。"])
        }
        return sorted(document.entries)
    }
    static func sorted(_ entries: [WordbookEntry]) -> [WordbookEntry] {
        entries.sorted { $0.latestTime == $1.latestTime ? $0.id < $1.id : $0.latestTime > $1.latestTime }
    }

    /// Import only complete legacy answers. The newest successful first answer
    /// wins; later failures cannot erase it. Repeated definitions disappear,
    /// while distinct explicit follow-ups survive, even from older visits.
    static func parse(_ data: Data, fallbackBook: String) -> [WordbookEntry] {
        var visits = [String: LegacyVisit]()
        for line in data.split(separator: 0x0a) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let event = row["event"] as? String, let id = row["sessionID"] as? String else { continue }
            if event == "selection_received" || (event == "answer" && visits[id] == nil) {
                guard let text = row["selection"] as? String, !key(text).isEmpty else { continue }
                visits[id] = LegacyVisit(id: id, selection: key(text),
                    book: row["bookTitle"] as? String ?? fallbackBook, time: row["time"] as? String ?? "")
            }
            guard var visit = visits[id] else { continue }
            if event == "request_started" { visit.automatic = row["automatic"] as? Bool ?? false }
            if event == "answer", let answer = row["answer"] as? String, !key(answer).isEmpty {
                visit.exchanges.append(WordbookExchange(question: row["question"] as? String ?? "", answer: answer, automatic: visit.automatic))
            }
            visits[id] = visit
        }
        let groups = Dictionary(grouping: visits.values, by: \.selection)
        return sorted(groups.map { term, visits in
            let ordered = visits.sorted { $0.time == $1.time ? $0.id > $1.id : $0.time > $1.time }
            let source = ordered.first(where: { !$0.exchanges.isEmpty }) ?? ordered[0]
            var exchanges = Array(source.exchanges.prefix(1))
            for visit in ordered.reversed() {
                for exchange in visit.exchanges.dropFirst() where !exchange.automatic {
                    if exchange.question == visit.exchanges.first?.question { continue }
                    if !exchanges.contains(where: { $0.question == exchange.question && $0.answer == exchange.answer }) {
                        exchanges.append(exchange)
                    }
                }
            }
            return WordbookEntry(selection: term, book: source.book, latestTime: ordered[0].time, exchanges: exchanges)
        })
    }
}

/// Disk I/O and migration run off the main actor. A failed read is an error, never
/// a cache miss; writes commit atomically before the in-memory version changes.
actor WordbookLibrary {
    static let shared = WordbookLibrary()
    let url: URL
    let historyURL: URL
    private var values: [String: WordbookEntry]?

    init(url: URL = WordbookStore.storeURL, historyURL: URL = WordbookStore.historyURL) {
        self.url = url; self.historyURL = historyURL
    }
    private func ensureLoaded(fallbackBook: String) throws {
        guard values == nil else { return }
        let fm = FileManager.default
        let entries: [WordbookEntry]
        if fm.fileExists(atPath: url.path) {
            entries = try WordbookStore.decode(Data(contentsOf: url))
        } else {
            let exists = fm.fileExists(atPath: historyURL.path)
            let data = exists ? try Data(contentsOf: historyURL) : Data()
            entries = WordbookStore.parse(data, fallbackBook: fallbackBook)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if exists {
                let backup = url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let path = backup.appendingPathComponent("history-before-unique-" + UUID().uuidString + ".jsonl")
                try data.write(to: path, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            }
            try persist(Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }))
        }
        values = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }
    private func persist(_ next: [String: WordbookEntry]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(WordbookDocument(version: 1, entries: WordbookStore.sorted(Array(next.values)))).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func entries(fallbackBook: String) throws -> [WordbookEntry] {
        try ensureLoaded(fallbackBook: fallbackBook)
        return WordbookStore.sorted(Array(values!.values))
    }
    func lookup(_ selection: String, fallbackBook: String) throws -> WordbookEntry? {
        try ensureLoaded(fallbackBook: fallbackBook)
        return values![WordbookStore.key(selection)]
    }
    func select(_ selection: String, book: String, time: String) throws -> WordbookEntry {
        try ensureLoaded(fallbackBook: book)
        let key = WordbookStore.key(selection)
        guard !key.isEmpty else { throw NSError(domain: "Wordbook", code: 2) }
        var entry = values![key] ?? WordbookEntry(selection: key, book: book, latestTime: time, exchanges: [])
        entry.latestTime = time
        var next = values!; next[key] = entry
        try persist(next); values = next
        return entry
    }
    func save(_ selection: String, book: String, exchange: WordbookExchange, time: String) throws -> WordbookEntry {
        try ensureLoaded(fallbackBook: book)
        let key = WordbookStore.key(selection)
        guard !key.isEmpty, !WordbookStore.key(exchange.answer).isEmpty else { throw NSError(domain: "Wordbook", code: 2) }
        var entry = values![key] ?? WordbookEntry(selection: key, book: book, latestTime: time, exchanges: [])
        if entry.exchanges.isEmpty { entry.book = book; entry.exchanges = [exchange] }
        else if !exchange.automatic && !entry.exchanges.contains(where: { $0.question == exchange.question && $0.answer == exchange.answer }) {
            entry.exchanges.append(exchange)
        }
        entry.latestTime = time
        var next = values!; next[key] = entry
        try persist(next); values = next
        return entry
    }
}
