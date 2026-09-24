import AppKit

/// Intercepts every test model request in-process. No gateway, paid call, user
/// credentials, personal wordbook, window presentation or history writes.
final class CountingModel: URLProtocol {
    static var requests = 0
    static var mode = "complete"
    static var held: CountingModel?
    static let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let mode = Self.mode
        if mode == "hold" { Self.held = self }
        Self.lock.unlock()
        if mode != "hold" { finish(truncated: mode == "truncated") }
    }
    func finish(truncated: Bool = false) {
        guard !stopped else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"A complete test explanation.\"}}]}\n\n" + (truncated ? "" : "data: [DONE]\n\n")
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { stopped = true }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func setMode(_ value: String) { lock.lock(); mode = value; lock.unlock() }
}

@main struct WordbookCacheTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wordbook-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auth = root.appendingPathComponent("auth.json"), context = root.appendingPathComponent("context.json")
        try Data("{\"test\":{\"key\":\"isolated-test-credential\"}}".utf8).write(to: auth)
        try Data("[]".utf8).write(to: context)
        let url = root.appendingPathComponent("wordbook.json"), history = root.appendingPathComponent("history.jsonl")
        let library = WordbookLibrary(url: url, historyURL: history)
        _ = try await library.save("fragile", book: "Original book", exchange: WordbookExchange(question: "Explain", answer: "Easily damaged.", automatic: true), time: "2026-09-20")
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [CountingModel.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        var events: [[String: Any]] = []
        func makeOwner(_ library: WordbookLibrary) -> BookAsk {
            let owner = BookAsk(); owner.buildWindow()
            owner.wordbookLibrary = library; owner.modelSession = session
            owner.configurationLoader = { Configuration(baseURL: "https://book-ask-test.invalid/v1", authFile: auth.path, authProvider: "test", model: "test-model", contextFile: context.path, bookTitle: "Another book") }
            owner.config = try! owner.configurationLoader()
            owner.recordSink = { events.append($0) }
            owner.windowPresenter = { _ in }
            owner.autoExplain = true
            return owner
        }
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func wait(_ condition: () -> Bool) async {
            let deadline = Date().addingTimeInterval(5)
            while !condition() && Date() < deadline { await Task.yield() }
            check(condition(), "asynchronous request/lookup must settle within 5 seconds")
        }
        let savedSize = UserDefaults.standard.object(forKey: "answerFontSize")
        defer { UserDefaults.standard.set(savedSize, forKey: "answerFontSize") }
        let owner = makeOwner(library)
        func select(_ term: String) async {
            if CommandLine.arguments.contains("--old-no-cache") {
                owner.stop(); owner.selectedText = term; owner.currentWordbookEntry = nil
                owner.ask("Explain", automatic: true)
            } else { owner.receive(term, sampleID: "isolated-test") }
            await wait { owner.lookupTask == nil && owner.activeTask == nil }
        }
        await select("fragile")
        check(CountingModel.count == 0 && owner.transcript.string == "Easily damaged.", "existing exact term must return local answer with zero HTTP requests")
        owner.sendQuestion()
        check(CountingModel.count == 0, "empty send on cached term must not regenerate")
        await select("crate")
        check(CountingModel.count == 1, "new term makes exactly one request")
        await select("fragile")
        check(CountingModel.count == 1 && owner.messages.count == 2, "A → B → A reuses saved A")
        owner.autoExplain = false
        await select("crate")
        check(CountingModel.count == 1 && owner.currentWordbookEntry?.hasAnswer == true, "cache also displays with automatic explanation off")
        owner.autoExplain = true
        CountingModel.setMode("hold")
        owner.question.stringValue = "Can you give another example?"
        owner.sendQuestion()
        await wait { CountingModel.held != nil }
        owner.changeAnswerSize(to: 19)
        check(CountingModel.count == 2, "changing answer size during a held real request starts no additional request")
        CountingModel.held!.finish()
        CountingModel.setMode("complete")
        await wait { owner.activeTask == nil }
        owner.transcript.attributedString().enumerateAttribute(.font, in: NSRange(location: 0, length: owner.transcript.string.utf16.count)) { font, _, _ in
            check((font as? NSFont)?.pointSize == 19, "late SSE uses the changed answer size in every run")
        }
        check(CountingModel.count == 2 && owner.messages.count == 4, "explicit follow-up sends one request with restored conversation")
        let relaunched = makeOwner(WordbookLibrary(url: url, historyURL: history))
        relaunched.receive("crate", sampleID: "isolated-relaunch")
        await wait { relaunched.lookupTask == nil }
        check(relaunched.answerFontSize == 19 && relaunched.transcript.font?.pointSize == 19, "relaunch and cache restore retain answer size")
        check(CountingModel.count == 2 && relaunched.messages.count == 4, "restart uses persistent definition and follow-up without HTTP")
        // Queued cache reads must not paint over a newer selection.
        owner.receive("fragile", sampleID: "old-read")
        owner.receive("crate", sampleID: "new-read")
        await wait { owner.lookupTask == nil }
        check(owner.selectedText == "crate" && owner.transcript.string.contains("another example"), "newest selection owns UI")
        CountingModel.setMode("truncated")
        await select("unfinished")
        let incomplete = try await library.lookup("unfinished", fallbackBook: "Book")
        check(incomplete?.hasAnswer == false && owner.status.stringValue == "请求未完成", "partial SSE must not become a reusable answer")
        CountingModel.setMode("hold")
        owner.receive("pending", sampleID: "pending")
        await wait { CountingModel.count == 4 }
        owner.receive("pending", sampleID: "same-pending")
        check(CountingModel.count == 4, "same active term must not start another request")
        owner.stop()
        let cancelled = try await library.lookup("pending", fallbackBook: "Book")
        check(cancelled?.hasAnswer == false, "cancelled request must not enter answer cache")
        CountingModel.setMode("complete")
        let corruptURL = root.appendingPathComponent("corrupt.json")
        try Data("invalid".utf8).write(to: corruptURL)
        let broken = makeOwner(WordbookLibrary(url: corruptURL, historyURL: history))
        broken.receive("fragile", sampleID: "corrupt")
        await wait { broken.lookupTask == nil }
        broken.sendQuestion(); await wait { broken.lookupTask == nil }
        check(CountingModel.count == 4 && !broken.wordbookReady, "read failure and retry must not fall through to paid request")
        check(events.contains { $0["event"] as? String == "wordbook_cache_hit" }, "cache decisions must be observable")
        print("PASS: real BookAsk receive/send + intercepted HTTP counts: initial cache 0; A-B-A 1; empty send 0 additional; explicit follow-up 1; restart/cache-off 0; stale reads, partial SSE, cancelled/repeated in-flight and corrupt reads protected")
    }
}
