import Foundation

struct WordbookExchange {
    let question: String
    let answer: String
    let automatic: Bool
}

struct WordbookVisit {
    let id: String
    let selection: String
    let book: String
    let time: String
    var exchanges: [WordbookExchange] = []
    var automatic = false
    var status = "尚未生成解释"
}

struct WordbookEntry {
    let id: String
    let selection: String
    let book: String
    let visits: [WordbookVisit]
    var latestTime: String { visits.first?.time ?? "" }

    func matches(_ query: String) -> Bool {
        query.isEmpty || ([selection, book] + visits.flatMap { $0.exchanges.flatMap { [$0.question, $0.answer] } })
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum WordbookStore {
    static var historyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BookAsk/history.jsonl")
    }

    static func load(fallbackBook: String) throws -> [WordbookEntry] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return parse(try Data(contentsOf: historyURL), fallbackBook: fallbackBook)
    }

    // The append-only history is the source of truth. Ignore diagnostics and a
    // possible unfinished last line without altering or migrating the history.
    static func parse(_ data: Data, fallbackBook: String) -> [WordbookEntry] {
        var visits = [String: WordbookVisit]()
        for line in data.split(separator: 0x0a) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let event = row["event"] as? String,
                  let id = row["sessionID"] as? String else { continue }
            if event == "selection_received" || (event == "answer" && visits[id] == nil) {
                guard let text = row["selection"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                visits[id] = WordbookVisit(id: id, selection: text,
                    book: row["bookTitle"] as? String ?? fallbackBook, time: row["time"] as? String ?? "")
            }
            guard var visit = visits[id] else { continue }
            switch event {
            case "request_started":
                visit.automatic = row["automatic"] as? Bool ?? false
                visit.status = "尚无完整回答"
            case "answer":
                if let answer = row["answer"] as? String, !answer.isEmpty {
                    visit.exchanges.append(WordbookExchange(question: row["question"] as? String ?? "",
                        answer: answer, automatic: visit.automatic))
                    visit.status = ""
                }
            case "cancelled": visit.status = "上次回答已停止"
            case "error": visit.status = "上次请求未完成"
            default: break
            }
            visits[id] = visit
        }
        let groups = Dictionary(grouping: visits.values) { visit in
            visit.book + "\u{0}" + visit.selection.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        }
        return groups.map { id, visits in
            let ordered = visits.sorted { $0.time == $1.time ? $0.id > $1.id : $0.time > $1.time }
            return WordbookEntry(id: id, selection: ordered[0].selection, book: ordered[0].book, visits: ordered)
        }.sorted { $0.latestTime == $1.latestTime ? $0.id < $1.id : $0.latestTime > $1.latestTime }
    }
}
