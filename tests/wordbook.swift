import Foundation

@main struct WordbookTests {
    static func main() async throws {
        func check(_ value: Bool, _ message: String = "wordbook assertion") { precondition(value, message) }
        let rows: [[String: Any]] = [
            ["event":"selection_received", "sessionID":"a", "selection":"fragile", "time":"2026-09-18T01:00:00Z"],
            ["event":"request_started", "sessionID":"a", "automatic":true],
            ["event":"selection_received", "sessionID":"b", "selection":"liable to", "time":"2026-09-18T02:00:00Z"],
            ["event":"answer", "sessionID":"a", "answer":"Old definition.", "question":"template"],
            ["event":"request_started", "sessionID":"a", "automatic":false],
            ["event":"answer", "sessionID":"a", "answer":"The glass is fragile.", "question":"One example?"],
            ["event":"selection_received", "sessionID":"c", "selection":"fragile", "time":"2026-09-18T03:00:00Z"],
            ["event":"request_started", "sessionID":"c", "automatic":true],
            ["event":"answer", "sessionID":"c", "answer":"Newest complete definition.", "question":"template"],
            ["event":"selection_received", "sessionID":"d", "selection":"fragile", "bookTitle":"Another book", "time":"2026-09-18T04:00:00Z"],
            ["event":"error", "sessionID":"d"],
            ["event":"selection_received", "sessionID":"e", "selection":"Fragile", "time":"2026-09-18T05:00:00Z"],
            ["event":"selection_received", "sessionID":"f", "selection":"fragile.", "time":"2026-09-18T06:00:00Z"],
            ["event":"selection_received", "sessionID":"g", "selection":"liable  to", "time":"2026-09-18T07:00:00Z"],
            ["event":"selection_tick", "sessionID":"h"]
        ]
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        data.append(Data("{unfinished".utf8))
        let entries = WordbookStore.parse(data, fallbackBook:"The Mom Test")
        check(entries.count == 5, "Exact identity preserves case, punctuation and inner spaces; crosses books")
        let fragile = entries.first { $0.selection == "fragile" }!
        check(fragile.exchanges.count == 2, "Only one definition plus the meaningful follow-up")
        check(fragile.exchanges[0].answer == "Newest complete definition.", "A later failure must not replace success")
        check(fragile.exchanges[1].question == "One example?" && fragile.matches("GLASS"))
        check(!entries.first { $0.selection == "liable to" }!.hasAnswer)
        check(WordbookStore.parse(Data(), fallbackBook:"Book").isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wordbook-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("wordbook.json"), history = root.appendingPathComponent("history.jsonl")
        try data.write(to: history)
        let library = WordbookLibrary(url: url, historyURL: history)
        let first = try await library.entries(fallbackBook: "The Mom Test")
        check(first.count == 5)
        let backup = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        let backupData = try Data(contentsOf: backup[0])
        check(backup.count == 1 && backupData == data, "Migration makes an exact backup")
        check((try Data(contentsOf: history)) == data, "Raw diagnostic history remains intact")
        _ = try await library.select("fragile", book: "Third book", time: "2026-09-20")
        _ = try await library.save("fragile", book: "Third book", exchange: WordbookExchange(question: "template", answer: "Should not replace definition", automatic: true), time: "2026-09-20")
        let reopened = WordbookLibrary(url: url, historyURL: history)
        let cached = try await reopened.lookup("fragile", fallbackBook: "Book")!
        check(cached.exchanges == fragile.exchanges)
        check((try await reopened.entries(fallbackBook: "Book")).count == 5)
        check((try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path)).count == 1, "Repeated launch does not remigrate")
        let damaged = root.appendingPathComponent("damaged.json")
        try Data("broken".utf8).write(to: damaged)
        do { _ = try await WordbookLibrary(url: damaged, historyURL: history).lookup("fragile", fallbackBook: "Book"); fatalError("A read error must not be a cache miss") } catch {}
        check((try Data(contentsOf: damaged)) == Data("broken".utf8))
        let snapshot = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do { _ = try await library.save("new", book: "Book", exchange: WordbookExchange(question: "q", answer: "a", automatic: true), time: "now"); fatalError("write must fail") } catch {}
        check(try await library.lookup("new", fallbackBook: "Book") == nil, "Failed writes cannot enter the cache")
        try FileManager.default.removeItem(at: url); try snapshot.write(to: url)
        print("PASS: exact unique terms; latest full definition plus preserved follow-ups; backup/idempotent migration; restart cache; corrupted reads and failed writes stay safe")
    }
}
