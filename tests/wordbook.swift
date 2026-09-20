import Foundation

@main struct WordbookTests {
    static func main() throws {
        let rows: [[String: Any]] = [
            ["event":"selection_received", "sessionID":"a", "selection":"Fragile", "time":"2026-09-18T01:00:00Z"],
            ["event":"request_started", "sessionID":"a", "automatic":true],
            ["event":"selection_received", "sessionID":"b", "selection":"liable to", "time":"2026-09-18T02:00:00Z"],
            ["event":"answer", "sessionID":"a", "answer":"Easily damaged.", "question":"template"],
            ["event":"request_started", "sessionID":"a", "automatic":false],
            ["event":"answer", "sessionID":"a", "answer":"The glass is fragile.", "question":"One example?"],
            ["event":"selection_received", "sessionID":"c", "selection":"fragile", "time":"2026-09-18T03:00:00Z"],
            ["event":"cancelled", "sessionID":"c"],
            ["event":"selection_received", "sessionID":"d", "selection":"fragile", "bookTitle":"Another book", "time":"2026-09-18T04:00:00Z"],
            ["event":"selection_tick", "sessionID":"e"]
        ]
        var data = Data()
        for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(10) }
        data.append(Data("{unfinished".utf8))
        let entries = WordbookStore.parse(data, fallbackBook:"The Mom Test")
        precondition(entries.count == 3, "Duplicate terms merge within a book, not across books")
        precondition(entries[0].book == "Another book", "Newest selection comes first")
        let fragile = entries[1]
        precondition(fragile.visits.count == 2 && fragile.visits[0].exchanges.isEmpty)
        precondition(fragile.visits[0].status == "上次回答已停止")
        precondition(fragile.visits[1].exchanges.count == 2, "Interleaved sessions retain their own answers")
        precondition(fragile.visits[1].exchanges[0].automatic && !fragile.visits[1].exchanges[1].automatic)
        precondition(fragile.matches("GLASS") && !fragile.matches("nonexistent"))
        precondition(entries[2].visits[0].status == "尚未生成解释")
        precondition(WordbookStore.parse(Data(), fallbackBook:"Book").isEmpty)
        if CommandLine.arguments.contains("--local-history") {
            let local = try WordbookStore.load(fallbackBook:"The Mom Test")
            precondition(local.contains { $0.selection.lowercased() == "bulldozer" && $0.visits.contains { !$0.exchanges.isEmpty } })
            print("PASS: local history loaded, \(local.count) wordbook entries, existing bulldozer answer preserved")
        }
        print("PASS: wordbook history grouping, session isolation, incomplete data, search and empty history")
    }
}
