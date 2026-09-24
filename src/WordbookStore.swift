import Foundation

struct WordbookExchange: Codable, Equatable, Sendable {
    let question: String
    let answer: String
    let automatic: Bool
}

/// Each definition owns its source context and follow-up conversation.
struct WordbookDefinition: Codable, Equatable, Sendable {
    var id: String
    var book: String
    var createdAt: String
    var contextText: String
    var contextStatus: String
    var exchanges: [WordbookExchange]
}

struct WordbookEntry: Codable, Sendable {
    var selection: String
    var latestTime: String
    var definitions: [WordbookDefinition]
    private var emptyBook: String
    var id: String { selection }
    var book: String {
        get { definitions.first?.book ?? emptyBook }
        set { emptyBook = newValue; if !definitions.isEmpty { definitions[0].book = newValue } }
    }
    // Compatibility projections for existing renderers and v1 import.
    var exchanges: [WordbookExchange] {
        get { definitions.first?.exchanges ?? [] }
        set {
            if definitions.isEmpty {
                if !newValue.isEmpty { definitions = [WordbookDefinition(id: UUID().uuidString, book: emptyBook,
                    createdAt: latestTime, contextText: "", contextStatus: "旧记录未保存语境", exchanges: newValue)] }
            } else { definitions[0].exchanges = newValue }
        }
    }
    init(selection: String, book: String, latestTime: String, exchanges: [WordbookExchange]) {
        self.selection = selection; self.latestTime = latestTime; emptyBook = book; definitions = []
        self.exchanges = exchanges
    }
    private enum CodingKeys: String, CodingKey { case selection, book, latestTime, exchanges, definitions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selection = try c.decode(String.self, forKey: .selection)
        latestTime = try c.decode(String.self, forKey: .latestTime)
        emptyBook = try c.decodeIfPresent(String.self, forKey: .book) ?? "图书"
        definitions = try c.decodeIfPresent([WordbookDefinition].self, forKey: .definitions) ?? []
        if !c.contains(.definitions) { exchanges = try c.decode([WordbookExchange].self, forKey: .exchanges) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selection, forKey: .selection); try c.encode(latestTime, forKey: .latestTime)
        try c.encode(book, forKey: .book); try c.encode(definitions, forKey: .definitions)
    }
    func displaying(_ id: String?) -> WordbookEntry {
        var copy = self
        if let id, let item = definitions.first(where: { $0.id == id }) { copy.definitions = [item] }
        return copy
    }
    var hasAnswer: Bool { !definitions.isEmpty }
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
        query.isEmpty || ([selection] + definitions.flatMap { [$0.book] + $0.exchanges.flatMap { [$0.question, $0.answer] } })
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct DeletedDefinition: Sendable {
    let term: String
    let definition: WordbookDefinition?
    let index: Int
    let book: String
    let time: String
    var entireEntry: WordbookEntry? = nil
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
        guard [1, 2].contains(document.version),
              Set(document.entries.map(\.id)).count == document.entries.count,
              document.entries.allSatisfy({ !$0.id.isEmpty && $0.id == key($0.id) && Set($0.definitions.map(\.id)).count == $0.definitions.count && $0.definitions.allSatisfy { !$0.id.isEmpty && !$0.exchanges.isEmpty && $0.exchanges.allSatisfy { !key($0.answer).isEmpty } } }) else {
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
    private var deletionRevisions: [String: Int] = [:]

    init(url: URL = WordbookStore.storeURL, historyURL: URL = WordbookStore.historyURL) {
        self.url = url; self.historyURL = historyURL
    }
    private func ensureLoaded(fallbackBook: String) throws {
        guard values == nil else { return }
        let fm = FileManager.default
        let entries: [WordbookEntry]
        if fm.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            entries = try WordbookStore.decode(data)
            if (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int == 1 {
                let backup = url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let original = backup.appendingPathComponent("wordbook-v1-" + UUID().uuidString + ".json")
                try data.write(to: original, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
                try persist(Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }))
            }
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
        try encoder.encode(WordbookDocument(version: 2, entries: WordbookStore.sorted(Array(next.values)))).write(to: url, options: .atomic)
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
    func requestRevision(_ term: String) throws -> Int {
        try ensureLoaded(fallbackBook: "图书")
        let key = WordbookStore.key(term)
        guard values![key] != nil else { throw NSError(domain: "Wordbook", code: 4, userInfo: [NSLocalizedDescriptionKey: "该词条已被删除。"] ) }
        return deletionRevisions[key, default: 0]
    }
    func appendDefinition(_ term: String, book: String, contextText: String, contextStatus: String,
                          exchange: WordbookExchange, time: String, expectedRevision: Int? = nil) throws -> WordbookEntry {
        try ensureLoaded(fallbackBook: book)
        let key = WordbookStore.key(term)
        if let expectedRevision, deletionRevisions[key, default: 0] != expectedRevision {
            throw NSError(domain: "Wordbook", code: 3, userInfo: [NSLocalizedDescriptionKey: "该词条已被删除，未保存晚到的回答。"])
        }
        guard !key.isEmpty, !WordbookStore.key(exchange.answer).isEmpty else { throw NSError(domain: "Wordbook", code: 2) }
        var entry = values![key] ?? WordbookEntry(selection: key, book: book, latestTime: time, exchanges: [])
        entry.definitions.append(WordbookDefinition(id: UUID().uuidString, book: book, createdAt: time,
            contextText: contextText, contextStatus: contextStatus, exchanges: [exchange]))
        entry.latestTime = time
        var next = values!; next[key] = entry; try persist(next); values = next
        return entry
    }
    func appendFollowup(_ term: String, definitionID: String, exchange: WordbookExchange, time: String) throws -> WordbookEntry {
        try ensureLoaded(fallbackBook: "图书")
        let key = WordbookStore.key(term)
        guard var entry = values![key], let i = entry.definitions.firstIndex(where: { $0.id == definitionID }) else {
            throw NSError(domain: "Wordbook", code: 3, userInfo: [NSLocalizedDescriptionKey: "这份解释已被删除，未重新保存。"])
        }
        entry.definitions[i].exchanges.append(exchange); entry.latestTime = time
        var next = values!; next[key] = entry; try persist(next); values = next
        return entry
    }
    func delete(_ term: String, definitionID: String?) throws -> DeletedDefinition {
        try ensureLoaded(fallbackBook: "图书")
        let key = WordbookStore.key(term)
        guard var entry = values![key] else { throw NSError(domain: "Wordbook", code: 4) }
        let index: Int
        let definition: WordbookDefinition?
        if let id = definitionID, let i = entry.definitions.firstIndex(where: { $0.id == id }) {
            index = i; definition = entry.definitions.remove(at: i)
        } else if definitionID == nil && entry.definitions.isEmpty { index = 0; definition = nil }
        else { throw NSError(domain: "Wordbook", code: 4) }
        let token = DeletedDefinition(term: key, definition: definition, index: index, book: entry.book, time: entry.latestTime)
        var next = values!
        if entry.definitions.isEmpty { next.removeValue(forKey: key) } else { next[key] = entry }
        try persist(next); values = next
        deletionRevisions[key, default: 0] += 1
        return token
    }
    func deleteTerm(_ term: String) throws -> DeletedDefinition {
        try ensureLoaded(fallbackBook: "图书")
        let key = WordbookStore.key(term)
        guard let entry = values![key] else { throw NSError(domain: "Wordbook", code: 4) }
        let token = DeletedDefinition(term: key, definition: nil, index: 0, book: entry.book, time: entry.latestTime, entireEntry: entry)
        var next = values!; next.removeValue(forKey: key)
        try persist(next); values = next
        deletionRevisions[key, default: 0] += 1
        return token
    }
    func undo(_ token: DeletedDefinition) throws {
        try ensureLoaded(fallbackBook: token.book)
        var entry = values![token.term] ?? WordbookEntry(selection: token.term, book: token.book, latestTime: token.time, exchanges: [])
        if let original = token.entireEntry {
            let originalIDs = Set(original.definitions.map(\.id))
            entry.definitions = original.definitions + entry.definitions.filter { !originalIDs.contains($0.id) }
            entry.latestTime = max(entry.latestTime, original.latestTime)
        } else if let definition = token.definition, !entry.definitions.contains(where: { $0.id == definition.id }) {
            // Original save order survives a concurrent append while the undo banner was visible.
            entry.definitions.insert(definition, at: min(token.index, entry.definitions.count))
        }
        var next = values!; next[token.term] = entry; try persist(next); values = next
    }

}
