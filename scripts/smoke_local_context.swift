import AppKit

/// Live model integration using a previously observed Books page, isolated
/// storage and the production controller. This is not a physical-gesture or
/// installed-binary E2E test. It deliberately leaves the installed index empty.
@main struct LocalContextSmoke {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            fputs("Usage: local-context-smoke private-profile.json book-evidence output\n", stderr)
            exit(2)
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = try Configuration.load(homeDirectory: output, bundledConfigurationURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let key = try config.credential()
        let input = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("actual-books-passages.json")
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: input)) as! [[String: Any]]
        let page = ReadingPageSnapshot(bookTitle: "The Wonderful Wizard of Oz", visibleText: rows[1]["visiblePassage"] as! String, selectedRange: nil)
        let local = LocalBookContext(indexDirectory: output.appendingPathComponent("Indexes"))
        let owner = BookAsk()
        var events = [[String: Any]]()
        owner.recordSink = { events.append($0) }; owner.windowPresenter = { _ in }
        owner.configurationLoader = { config }
        owner.contextResolver = { term, snapshot in await local.resolve(selection: term, page: snapshot) }
        owner.wordbookLibrary = WordbookLibrary(url: output.appendingPathComponent("wordbook.json"), historyURL: output.appendingPathComponent("history.jsonl"))
        owner.autoExplain = true; owner.buildWindow()
        let savedCache = UserDefaults.standard.object(forKey: "answerCacheEnabled")
        defer { UserDefaults.standard.set(savedCache, forKey: "answerCacheEnabled") }
        ReadingPreferences.cacheEnabled = true
        func settle() async throws {
            let deadline = Date().addingTimeInterval(100)
            while owner.lookupTask != nil || owner.activeTask != nil {
                guard Date() < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        owner.receive("sad plight", sampleID: "observed-page-live-model", page: page)
        try await settle()
        let firstID = owner.activeDefinitionID
        let initial = owner.currentWordbookEntry?.definitions.first
        if initial != nil {
            owner.addExplanation(); try await settle()
            owner.question.stringValue = "Does plight usually describe a difficult situation? Answer in one sentence."
            owner.sendQuestion(); try await settle()
        }
        let saved = owner.currentWordbookEntry
        let requestsBefore = events.filter { $0["event"] as? String == "request_started" }.count
        owner.receive("sad plight", sampleID: "observed-page-reuse", page: page); try await settle()
        let requestsAfter = events.filter { $0["event"] as? String == "request_started" }.count
        let passed = initial?.book == page.bookTitle && initial?.contextStatus.contains("前200词 / 后200词") == true
            && saved?.definitions.count == 2 && saved?.definitions.last?.exchanges.count == 2
            && requestsBefore == 3 && requestsAfter == 3 && owner.activeDefinitionID == firstID
            && events.filter { $0["event"] as? String == "first_content" }.count == 3
        let result: [String: Any] = ["scope": "production_code_live_model_isolated_storage_not_installed_gesture_e2e", "passed": passed,
            "model": config.model, "requests": requestsAfter, "definitions": saved?.definitions.count ?? 0, "events": events]
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let safe = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: key, with: "[REDACTED]")
        try safe.write(to: output.appendingPathComponent("result.json"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.appendingPathComponent("result.json").path)
        print(passed ? "PASS: native cold index, 200+200 context, live streaming explanation/addition/follow-up, cache reuses first without request" : "FAIL: inspect result.json")
        if !passed { exit(1) }
    }
}
