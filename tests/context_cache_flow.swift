import AppKit

final class DefinitionModel: URLProtocol {
    static var requests = [[String: Any]]()
    static var mode = "complete"
    static var held: DefinitionModel?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
        }
        Self.requests.append((try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:])
        if Self.mode == "hold" { Self.held = self; return }
        finish(failed: Self.mode == "fail")
    }
    func finish(failed: Bool = false) {
        let response = HTTPURLResponse(url: request.url!, statusCode: failed ? 503 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"Fresh current-context answer.\"}}]}\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ContextCacheFlowTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("context-cache-flow-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheSetting = UserDefaults.standard.object(forKey: "answerCacheEnabled")
        defer { UserDefaults.standard.set(cacheSetting, forKey: "answerCacheEnabled") }
        ReadingPreferences.cacheEnabled = true
        let library = WordbookLibrary(url: root.appendingPathComponent("wordbook.json"), historyURL: root.appendingPathComponent("history.jsonl"))
        let first = try await library.appendDefinition("bank", book: "Old book", contextText: "Old financial context", contextStatus: "saved", exchange: .init(question: "Explain", answer: "Old financial answer.", automatic: true), time: "2026-01-01")
        let owner = BookAsk(); owner.buildWindow(); owner.wordbookLibrary = library
        owner.configurationLoader = { Configuration(baseURL: "https://isolated.invalid/v1", model: "test", apiKey: "fake-isolated-test") }
        owner.config = try owner.configurationLoader(); owner.recordSink = { _ in }; owner.windowPresenter = { _ in }; owner.autoExplain = true
        owner.contextResolver = { _, _ in LocalContextResult(book: "New book", text: "Current river context", status: "current") }
        let conf = URLSessionConfiguration.ephemeral; conf.protocolClasses = [DefinitionModel.self]
        owner.modelSession = URLSession(configuration: conf)
        defer { owner.modelSession.invalidateAndCancel() }
        func check(_ ok: Bool, _ message: String) { if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        func settle() async {
            let deadline = Date().addingTimeInterval(8)
            while (owner.activeTask != nil || owner.lookupTask != nil) && Date() < deadline { await Task.yield() }
            check(owner.activeTask == nil && owner.lookupTask == nil, "operation settles")
        }
        owner.receive("bank", sampleID: "first"); await settle()
        check(DefinitionModel.requests.isEmpty && owner.transcript.string == "Old financial answer.", "cache on reuses first without HTTP")
        DefinitionModel.mode = "hold"; owner.addExplanation()
        while DefinitionModel.held == nil { await Task.yield() }
        check(owner.transcript.string == "Old financial answer." && owner.addExplanationButton.isEnabled == false, "new explanation retains old answer while pending and disallows duplicate click")
        DefinitionModel.held!.finish(); DefinitionModel.mode = "complete"; await settle()
        let messages = DefinitionModel.requests[0]["messages"] as! [[String: String]]
        check(messages.count == 3 && messages[1]["content"]!.contains("Current river context") && messages[1]["content"]!.contains("New book") && !messages.description.contains("Old financial"), "plus uses current context with no old answer or old book")
        check(owner.currentWordbookEntry!.definitions.count == 2, "plus appends independent definition")
        let before = owner.transcript.string
        DefinitionModel.mode = "fail"; owner.addExplanation(); await settle()
        check(owner.transcript.string == before && owner.currentWordbookEntry!.definitions.count == 2, "failed append preserves old display and saved definitions")
        DefinitionModel.mode = "complete"
        ReadingPreferences.cacheEnabled = false
        owner.receive("bank", sampleID: "off-1"); await settle()
        owner.receive("bank", sampleID: "off-2"); await settle()
        check(DefinitionModel.requests.count == 4 && owner.currentWordbookEntry!.definitions.count == 4, "cache off same term in two new gestures makes two requests")
        owner.receive("bank", sampleID: "off-2"); await settle()
        check(DefinitionModel.requests.count == 4, "duplicate callback makes no extra request")
        owner.autoExplain = false; owner.receive("bank", sampleID: "off-manual"); await settle()
        check(DefinitionModel.requests.count == 4 && owner.transcript.string.isEmpty, "cache off does not override automatic sending off")
        owner.sendQuestion(); await settle()
        check(DefinitionModel.requests.count == 5, "manual send works with both switches off")
        ReadingPreferences.cacheEnabled = true
        _ = try await library.delete("bank", definitionID: first.definitions[0].id)
        owner.receive("bank", sampleID: "after-delete"); await settle()
        check(owner.transcript.string == "Fresh current-context answer." && DefinitionModel.requests.count == 5, "deleted first answer not served from in-memory cache")

        // A same-word gesture can move to another book while the displayed
        // cached answer and the user's unfinished follow-up remain intact.
        owner.question.stringValue = "My unfinished question"
        owner.contextResolver = { _, page in
            LocalContextResult(book: page!.bookTitle, text: page!.visibleText, status: "current")
        }
        owner.activeCaptureID = "moved-location"
        owner.finishCopyCapture(CaptureOutcome(captureID: "moved-location", strategy: "isolated-test", acceptedText: "bank"), pid: 0,
            placement: nil, page: .init(bookTitle: "Third book", visibleText: "Third location beside the river bank", selectedRange: nil))
        let contextDeadline = Date().addingTimeInterval(8)
        while owner.selectionContextTask != nil && Date() < contextDeadline { await Task.yield() }
        check(owner.selectionContextTask == nil && owner.question.stringValue == "My unfinished question", "same-word location refresh completes without losing draft")
        check(owner.selectionBook == "Third book" && DefinitionModel.requests.count == 5, "same-word location refresh does not request an answer")
        DefinitionModel.mode = "hold"; DefinitionModel.held = nil
        let savedCount = owner.currentWordbookEntry!.definitions.count
        let savedAnswer = owner.transcript.string
        owner.addExplanation()
        let requestDeadline = Date().addingTimeInterval(8)
        while DefinitionModel.held == nil && Date() < requestDeadline { await Task.yield() }
        check(DefinitionModel.held != nil, "new-location plus request starts")
        let movedMessages = DefinitionModel.requests.last!["messages"] as! [[String: String]]
        check(movedMessages.count == 3 && movedMessages[1]["content"]!.contains("Third book") && movedMessages[1]["content"]!.contains("Third location"), "same-word plus uses the new location with no cached conversation")
        owner.stop()
        await settle()
        let afterCancel = try await library.lookup("bank", fallbackBook: "")
        check(owner.transcript.string == savedAnswer && afterCancel!.definitions.count == savedCount, "cancelled addition preserves previous answer and definitions")
        print("PASS: actual BookAsk cache ON/OFF, fresh gestures vs duplicate callbacks, automatic-send independence, plus current context, preserved old answer on failure, deletion invalidation")
    }
}
