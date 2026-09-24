import Foundation

@main struct DefinitionTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("definition-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("wordbook.json"), history = root.appendingPathComponent("history.jsonl")
        let v1 = #"{"version":1,"entries":[{"selection":"bank","book":"Old book","latestTime":"2026-01-01","exchanges":[{"question":"Explain","answer":"Financial institution.","automatic":true},{"question":"Example?","answer":"I went to the bank.","automatic":false}]}]}"#
        try Data(v1.utf8).write(to: url)
        let library = WordbookLibrary(url: url, historyURL: history)
        func check(_ ok: Bool, _ message: String) { if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        let original = try await library.lookup("bank", fallbackBook: "")!
        check(original.definitions.count == 1 && original.exchanges.count == 2, "v1 keeps original definition and follow-up")
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        let backupBytes = try Data(contentsOf: files[0])
        check(files.count == 1 && backupBytes == Data(v1.utf8), "byte exact v1 backup")
        let firstID = original.definitions[0].id
        let extra = try await library.appendDefinition("bank", book: "River book", contextText: "river bank", contextStatus: "current", exchange: .init(question: "Explain", answer: "The side of a river.", automatic: true), time: "2026-02-01")
        check(extra.definitions.count == 2 && extra.exchanges[0].answer == "Financial institution.", "new meaning appended, oldest retained")
        let secondID = extra.definitions[1].id
        let removed = try await library.delete("bank", definitionID: firstID)
        let current = try await library.lookup("bank", fallbackBook: "")!
        check(current.definitions[0].id == secondID, "delete first makes second the cache source")
        do {
            _ = try await library.appendFollowup("bank", definitionID: firstID, exchange: .init(question: "late", answer: "late", automatic: false), time: "2026-03-01")
            check(false, "deleted definition must reject late writes")
        } catch {}
        _ = try await library.appendDefinition("bank", book: "Third book", contextText: "third", contextStatus: "current", exchange: .init(question: "Explain", answer: "Third interpretation", automatic: true), time: "2026-03-01")
        try await library.undo(removed)
        let restored = try await library.lookup("bank", fallbackBook: "")!
        check(restored.definitions.count == 3 && restored.definitions[0].id == firstID && restored.exchanges.count == 2, "undo merges with later append, retains original follow-up")
        let requestRevision = try await library.requestRevision("bank")
        let wholeTerm = try await library.deleteTerm("bank")
        check(try await library.lookup("bank", fallbackBook: "") == nil, "list delete removes every definition and follow-up")
        _ = try await library.select("bank", book: "New visit", time: "2026-04-01")
        do {
            _ = try await library.appendDefinition("bank", book: "Old request", contextText: "", contextStatus: "", exchange: .init(question: "late", answer: "late", automatic: true), time: "2026-04-01", expectedRevision: requestRevision)
            check(false, "late answer must not recreate a deleted term even after a new visit")
        } catch {}
        let newer = try await library.appendDefinition("bank", book: "New visit", contextText: "", contextStatus: "", exchange: .init(question: "Explain", answer: "New answer after deletion", automatic: true), time: "2026-04-01")
        try await library.undo(wholeTerm)
        let wholeRestored = try await library.lookup("bank", fallbackBook: "")!
        check(wholeRestored.definitions.map(\.id) == restored.definitions.map(\.id) + newer.definitions.map(\.id), "whole-term undo preserves original order and newer answers")
        check(wholeRestored.definitions[0].exchanges.count == 2, "whole-term undo restores associated follow-ups")
        _ = try await library.deleteTerm("bank")
        try await library.undo(wholeTerm)
        for definition in restored.definitions { _ = try await library.delete("bank", definitionID: definition.id) }
        check(try await library.lookup("bank", fallbackBook: "") == nil, "last deletion removes term")
        let restarted = WordbookLibrary(url: url, historyURL: history)
        check(try await restarted.lookup("bank", fallbackBook: "") == nil, "deleted term never revived on restart")
        _ = try await restarted.select("empty", book: "Book", time: "today")
        let empty = try await restarted.delete("empty", definitionID: nil)
        try await restarted.undo(empty)
        check(try await restarted.lookup("empty", fallbackBook: "")?.hasAnswer == false, "empty term delete and undo")
        print("PASS: v1 migration/backup; append; oldest cache; delete; undo merge; stale follow-up rejection; restart; empty term")
    }
}
