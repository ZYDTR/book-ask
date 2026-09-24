import AppKit

/// Opt-in paid smoke test of the production request, streaming UI and wordbook
/// code. Uses isolated storage; does not simulate a Books selection gesture.
@main struct ProductSmoke {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: product-smoke private-profile.json evidence-directory\n", stderr)
            exit(2)
        }
        _ = NSApplication.shared
        let profile = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let isolated = output.appendingPathComponent("isolated-product", isDirectory: true)
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        let config = try Configuration.load(homeDirectory: isolated, bundledConfigurationURL: profile)
        let key = try config.credential()
        let owner = BookAsk()
        var events: [[String: Any]] = []
        owner.recordSink = { events.append($0) }
        owner.windowPresenter = { _ in }
        owner.configurationLoader = { config }
        owner.wordbookLibrary = WordbookLibrary(url: isolated.appendingPathComponent("wordbook.json"),
            historyURL: isolated.appendingPathComponent("history.jsonl"))
        owner.autoExplain = true
        owner.buildWindow()
        func settle() async throws {
            let deadline = Date().addingTimeInterval(100)
            while owner.lookupTask != nil || owner.activeTask != nil {
                if Date() > deadline { throw URLError(.timedOut) }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        owner.receive("You're liable to get a biased answer.", sampleID: "paid-product-smoke")
        try await settle()
        let firstSaved = owner.currentWordbookEntry?.hasAnswer == true
        if firstSaved {
            owner.question.stringValue = "这里 liable to 和 likely to 有什么区别？请给一个简短例句。"
            owner.sendQuestion()
            try await settle()
        }
        let complete = firstSaved && owner.currentWordbookEntry?.exchanges.count == 2
            && owner.messages.count == 4
            && events.filter { $0["event"] as? String == "first_content" }.count == 2
        let result: [String: Any] = ["test": "paid_production_code_not_books_gesture_e2e",
            "model": config.model, "baseURL": config.baseURL, "thinkingLevel": config.thinkingLevel?.rawValue ?? "",
            "passed": complete, "status": owner.status.stringValue, "events": events]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let safe = String(decoding: json, as: UTF8.self).replacingOccurrences(of: key, with: "[REDACTED]")
        try safe.write(to: output.appendingPathComponent("product_smoke.json"), atomically: true, encoding: .utf8)
        for event in events where ["first_content", "answer", "error"].contains(event["event"] as? String ?? "") {
            print("\(event["event"] ?? "") turn=\(event["turn"] ?? "") elapsed=\(event["elapsedSeconds"] ?? "")")
        }
        owner.panel.orderOut(nil)
        print(complete ? "PASS: live streaming explanation, follow-up and isolated persistence" : "FAIL: inspect redacted product_smoke.json")
        exit(complete ? 0 : 1)
    }
}
