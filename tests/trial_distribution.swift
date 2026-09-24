import AppKit

/// Exercises the real request/wordbook/UI code with isolated data and an in-process
/// HTTP transport. These are integration tests, not Books or paid-model E2E.
final class TrialModel: URLProtocol {
    static var count = 0
    static var mode = "complete"
    static let fakeKey = "test-only-trial-secret"
    static var lastBody: [String: Any] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(contentsOf: buffer.prefix(n))
            }
        }
        Self.lastBody = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if Self.mode == "network" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        let code = Int(Self.mode) ?? 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let text: String
        if code != 200 { text = "error echoes \(Self.fakeKey)" }
        else if Self.mode == "stream" { text = "data: {\"error\":\"\(Self.fakeKey)\"}\n\n" }
        else { text = "data: {\"choices\":[{\"delta\":{\"content\":\"A concise test explanation.\"}}]}\n\ndata: [DONE]\n\n" }
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct TrialDistributionTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("book-ask-trial-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let fresh = try Configuration.load(homeDirectory: root, bundledConfigurationURL: nil)
        check(fresh.model.isEmpty && fresh.authFile.isEmpty && fresh.contextFile.isEmpty && fresh.bookTitle == "图书", "empty home starts without personal files or book")
        check(fresh.context(for: "a phrase").paragraphs.isEmpty, "no index uses only the selection")
        let profile = root.appendingPathComponent("trial.json")
        try JSONSerialization.data(withJSONObject: ["baseURL": "https://trial.invalid/v1", "model": "trial-model", "apiKey": TrialModel.fakeKey]).write(to: profile)
        let trial = try Configuration.load(homeDirectory: root, bundledConfigurationURL: profile)
        check(try trial.credential() == TrialModel.fakeKey, "bundled trial requires no external auth file")
        check(try trial.requestURL().absoluteString == "https://trial.invalid/v1/chat/completions", "route respects base path")
        check(trial.thinkingLevel == nil, "legacy profile has no new provider parameters")
        let geminiProfile = root.appendingPathComponent("gemini-trial.json")
        let geminiFields: [String: Any] = ["baseURL": "https://api.302.ai/v1", "model": "gemini-3.5-flash-lite",
            "apiKey": TrialModel.fakeKey, "thinkingLevel": "minimal"]
        try JSONSerialization.data(withJSONObject: geminiFields).write(to: geminiProfile)
        let gemini = try Configuration.load(homeDirectory: root, bundledConfigurationURL: geminiProfile)
        try JSONSerialization.data(withJSONObject: geminiFields.merging(["thinkingLevel": "unsupported"]) { _, new in new }).write(to: geminiProfile)
        do { _ = try Configuration.load(homeDirectory: root, bundledConfigurationURL: geminiProfile); fatalError("invalid thinking level must not silently use provider default") }
        catch { check(error is ConfigurationError, "invalid provider option is a sanitized configuration error") }
        let local = root.appendingPathComponent(".config/book-ask/config.json")
        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        let auth = root.appendingPathComponent("private-auth.json")
        try JSONSerialization.data(withJSONObject: ["old-provider": ["key": "test-only-private-key"]]).write(to: auth)
        try JSONSerialization.data(withJSONObject: ["baseURL": "https://private.invalid/v1", "model": "private-model",
            "authFile": auth.path, "authProvider": "old-provider", "bookTitle": "Private book", "contextFile": ""]).write(to: local)
        let legacy = try Configuration.load(homeDirectory: root, bundledConfigurationURL: profile)
        check(try legacy.credential() == "test-only-private-key", "legacy locator takes precedence over bundled trial")
        check(legacy.bookTitle == "Private book", "private book metadata is preserved locally")
        try Data("invalid json".utf8).write(to: local)
        do { _ = try Configuration.load(homeDirectory: root, bundledConfigurationURL: profile); fatalError("invalid local config must not silently use trial") }
        catch { check(error is ConfigurationError, "configuration error is sanitized") }
        let suite = "book-ask-trial-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(ReadingPreferences.copyCapture(in: defaults), "fresh preference enables guarded copy")
        defaults.set(false, forKey: "copyCaptureEnabled")
        check(!ReadingPreferences.copyCapture(in: defaults), "explicit old preference remains unchanged")
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [TrialModel.self]
        let transport = URLSession(configuration: sessionConfig)
        defer { transport.invalidateAndCancel() }
        let wordbook = root.appendingPathComponent("wordbook.json"), history = root.appendingPathComponent("history.jsonl")
        let library = WordbookLibrary(url: wordbook, historyURL: history)
        var events: [[String: Any]] = []
        let savedPrompt = UserDefaults.standard.object(forKey: "explanationPrompt")
        defer { UserDefaults.standard.set(savedPrompt, forKey: "explanationPrompt") }
        UserDefaults.standard.removeObject(forKey: "explanationPrompt")
        let promptDocument = try String(contentsOfFile: "docs/prompts.md", encoding: .utf8)
        let documentedPrompt = promptDocument.components(separatedBy: "```text\n")[1].components(separatedBy: "\n```")[0]
        check(ReadingPreferences.prompt == documentedPrompt, "a fresh installation uses the complete documented personal prompt")
        ReadingPreferences.prompt = "My later edited template"
        check(ReadingPreferences.prompt == "My later edited template", "an existing custom template stays above the shipped default")
        UserDefaults.standard.removeObject(forKey: "explanationPrompt")
        let owner = BookAsk()
        owner.recordSink = { events.append($0) }; owner.windowPresenter = { _ in }
        owner.wordbookLibrary = library; owner.modelSession = transport
        owner.autoExplain = true; owner.buildWindow()
        owner.configurationLoader = { fresh }
        func settle() async {
            let deadline = Date().addingTimeInterval(5)
            while (owner.lookupTask != nil || owner.activeTask != nil) && Date() < deadline { await Task.yield() }
            check(owner.lookupTask == nil && owner.activeTask == nil, "request returns to idle")
        }
        owner.receive("first unconfigured phrase", sampleID: "isolated")
        await settle()
        check(TrialModel.count == 0 && owner.transcript.string.contains("尚未配置"), "fresh app fails clearly without making a request")
        check(owner.currentWordbookEntry?.hasAnswer == false, "missing service does not cache a fake answer")
        owner.configurationLoader = { trial }
        for mode in ["401", "402", "429", "503", "network", "stream"] {
            TrialModel.mode = mode
            let before = TrialModel.count
            owner.receive("failure phrase " + mode, sampleID: "isolated")
            await settle()
            check(TrialModel.count == before + 1, "one attempt only; no automatic retry")
            check(owner.status.stringValue == "请求未完成" && owner.currentWordbookEntry?.hasAnswer == false, "failure displayed without saved answer")
            check(!owner.transcript.string.contains(TrialModel.fakeKey), "response body cannot expose key in UI")
        }
        TrialModel.mode = "complete"
        owner.receive("a new phrase", sampleID: "isolated")
        await settle()
        check(owner.currentWordbookEntry?.hasAnswer == true && owner.messages.count == 2, "first response saved")
        let firstMessages = TrialModel.lastBody["messages"] as? [[String: String]] ?? []
        check(firstMessages.last?["content"] == documentedPrompt && firstMessages.last?["role"] == "user",
              "the actual automatic request sends the full personal template")
        check(firstMessages.first?["content"] == ReadingPreferences.systemPrompt,
              "shared system accuracy and quoted-context boundary remain separate")
        check(TrialModel.lastBody["extra_body"] == nil, "existing provider profile sends unchanged request format")
        owner.question.stringValue = "Can you give an example?"; owner.sendQuestion()
        await settle()
        check(owner.messages.count == 4, "follow-up extends same conversation")
        let sent = TrialModel.lastBody["messages"] as? [[String: String]] ?? []
        check(sent.count == 5 && sent.contains { $0["role"] == "assistant" }, "follow-up transmits previous answer")
        TrialModel.mode = "401"
        owner.question.stringValue = "Explain the grammar."; owner.sendQuestion()
        await settle()
        check(owner.messages.count == 4 && owner.question.stringValue == "Explain the grammar.", "failed follow-up retains previous conversation and restores question")
        let restored = try await WordbookLibrary(url: wordbook, historyURL: history).select("a new phrase", book: "图书", time: "test")
        check(restored.exchanges.count == 2, "reopened wordbook retains only successful exchanges")
        let before = TrialModel.count
        owner.configurationLoader = { throw ConfigurationError.invalidFile }
        owner.receive("broken configuration", sampleID: "isolated")
        await settle()
        check(TrialModel.count == before && owner.config?.model.isEmpty == true && owner.transcript.string.contains("配置无法读取"), "bad config cannot reuse previous credentials")
        let log = String(data: try JSONSerialization.data(withJSONObject: events), encoding: .utf8)!
        check(!log.contains(TrialModel.fakeKey), "history/diagnostic boundary does not receive key")
        check(events.filter { $0["event"] as? String == "answer" }.count == 2, "only two successful answers recorded")
        owner.configurationLoader = { gemini }; TrialModel.mode = "complete"
        owner.receive("a gemini trial phrase", sampleID: "isolated")
        await settle()
        let extra = TrialModel.lastBody["extra_body"] as? [String: Any]
        let google = extra?["google"] as? [String: Any]
        let thinking = google?["thinking_config"] as? [String: String]
        check(TrialModel.lastBody["model"] as? String == "gemini-3.5-flash-lite"
            && TrialModel.lastBody["stream"] as? Bool == true
            && thinking?["thinking_level"] == "minimal", "real BookAsk request uses Gemini model, streaming and 302 thinking parameter")
        owner.question.stringValue = "Give another example."; owner.sendQuestion()
        await settle()
        check(owner.currentWordbookEntry?.exchanges.count == 2 && owner.messages.count == 4, "Gemini profile preserves follow-up and saved answers")

        // Save/Send revalidate the full draft even if the live edit notification
        // has not fired. All storage and HTTP transport remain isolated.
        for character in ["a", "字", "👩🏽‍💻", "e\u{301}", "\n", " "] {
            for count in [4999, 5000, 5001] {
                let input = String(repeating: character, count: count)
                check(input.count == count && InputLengthLimit.allows(input) == (count <= 5000),
                      "visible-character boundary: \(count)")
            }
        }
        let priorPrompt = owner.promptEditor.string
        let priorPreference = ReadingPreferences.prompt
        owner.togglePromptEditor()
        let tooLong = String(repeating: "字", count: 5001)
        owner.promptDraftEditor!.string = tooLong
        owner.promptDraftEditor!.didChangeText()
        check(owner.promptLimitLabel?.stringValue == "5001 / 5000", "typing updates the visible prompt count without truncating")
        owner.savePrompt()
        check(owner.promptExpanded && owner.promptDraftEditor?.string == tooLong
              && owner.promptEditor.string == priorPrompt && ReadingPreferences.prompt == priorPreference,
              "failed Save preserves the entire draft and accepted template")
        check(owner.promptGuidanceLabel?.stringValue.contains("未保存") == true, "failed Save explains why")
        let boundaryPrompt = String(repeating: "👩🏽‍💻", count: 5000)
        owner.promptDraftEditor!.string = boundaryPrompt
        owner.savePrompt()
        check(!owner.promptExpanded && ReadingPreferences.prompt == boundaryPrompt, "5000 visible characters save unchanged")
        owner.togglePromptEditor()
        check(owner.promptDraftEditor?.string == boundaryPrompt, "reopening preserves all 5000 characters")
        owner.cancelPrompt()
        owner.promptEditor.string = priorPrompt
        ReadingPreferences.prompt = priorPreference

        let calls = TrialModel.count, originalAnswer = owner.transcript.string, originalMessages = owner.messages
        owner.question.stringValue = tooLong
        owner.sendQuestion()
        owner.question.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: owner.panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        await settle()
        check(TrialModel.count == calls && owner.activeTask == nil && owner.question.stringValue == tooLong
              && owner.transcript.string == originalAnswer && owner.messages == originalMessages,
              "button and Return reject 5001 without HTTP, draft loss, or answer changes")
        check(owner.status.stringValue.contains("5000") && owner.status.stringValue.contains("未发送"),
              "send rejection and limit remain visible without a permanent counter")
        let whitespaceOverflow = " " + String(repeating: "a", count: 5000)
        owner.question.stringValue = whitespaceOverflow; owner.sendQuestion()
        check(TrialModel.count == calls && owner.question.stringValue == whitespaceOverflow, "trimming cannot bypass draft-length checks")
        let validQuestion = String(repeating: "问", count: 4999) + "?"
        owner.question.stringValue = validQuestion; owner.sendQuestion()
        await settle()
        let boundaryMessages = TrialModel.lastBody["messages"] as? [[String: String]] ?? []
        check(TrialModel.count == calls + 1 && boundaryMessages.last?["content"] == validQuestion
              && owner.question.stringValue.isEmpty, "correcting to 5000 sends once with the complete question")

        owner.promptEditor.string = " " + String(repeating: "a", count: 5000)
        let legacyTemplate = owner.promptEditor.string
        let beforeAutomatic = TrialModel.count
        owner.receive("legacy oversized template selection", sampleID: "isolated-length")
        await settle()
        check(TrialModel.count == beforeAutomatic && owner.promptEditor.string == legacyTemplate
              && owner.status.stringValue.contains("未发送"), "automatic path rejects the untrimmed legacy template")
        owner.sendQuestion()
        check(TrialModel.count == beforeAutomatic && owner.promptEditor.string == legacyTemplate,
              "empty manual Send cannot bypass the template cap")
        owner.ask(tooLong)
        check(TrialModel.count == beforeAutomatic && owner.activeTask == nil, "request boundary rejects direct oversized input")
        owner.promptEditor.string = String(repeating: "说", count: 5000)
        owner.sendQuestion(); await settle()
        let corrected = TrialModel.lastBody["messages"] as? [[String: String]] ?? []
        check(TrialModel.count == beforeAutomatic + 1 && corrected.last?["content"] == owner.promptEditor.string,
              "corrected 5000-character template sends completely")
        owner.panel.orderOut(nil)
        print("PASS: fresh install, trial/legacy configuration, errors, no retries, secret redaction, follow-up, persistence; 5000-character Save/Send limits, Unicode, preserved drafts and automatic-path validation")
    }
}
