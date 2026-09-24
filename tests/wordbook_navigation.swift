import AppKit

/// Real AppKit views and isolated library; no model/capture or personal history.
@main struct WordbookNavigationTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wordbook-nav-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WordbookLibrary(url: root.appendingPathComponent("wordbook.json"), historyURL: root.appendingPathComponent("history.jsonl"))
        _ = try await library.save("fragile", book: "Sample book", exchange: WordbookExchange(question: "Explain", answer: "Easily damaged.\n\nThe glass is fragile.", automatic: true), time: "2026-09-20")
        let longTerm = "a crate of dynamite for their excavation. They are, in one way or another, forcing people to say something nice."
        _ = try await library.save(longTerm, book: "Sample book", exchange: WordbookExchange(question: "Explain", answer: "Sample long entry", automatic: true), time: "2026-09-19")
        let owner = BookAsk(); owner.buildWindow()
        owner.wordbookLibrary = library
        var events: [[String: Any]] = []
        owner.recordSink = { events.append($0) }; owner.windowPresenter = { _ in }
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        owner.quote.string = "current word"; owner.transcript.string = "Existing reading answer"
        owner.question.stringValue = "My unsent question"
        owner.selectedText = "current word"
        owner.messages = [["role": "assistant", "content": "Existing reading answer"]]
        let generation = owner.activeGeneration
        let frame = owner.panel.frame, number = owner.panel.windowNumber
        let windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        owner.openWordbook()
        let page = owner.wordbook!
        let search = page.subviews.compactMap { $0 as? NSSearchField }.first!
        let table = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTableView }.first!
        let detail = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTextView }.first!
        let deadline = Date().addingTimeInterval(5)
        while table.numberOfRows == 0 && Date() < deadline { await Task.yield() }
        precondition(table.numberOfRows == 2 && !page.isShowingDetail, "loading must show the list without jumping to detail")
        page.layoutSubtreeIfNeeded()
        let longCell = table.view(atColumn: 0, row: 1, makeIfNecessary: true) as! NSTableCellView
        longCell.layoutSubtreeIfNeeded()
        precondition(longCell.textField!.frame.height > 30, "long terms must really occupy two lines, not one truncated line")
        let dateLabel = longCell.subviews.compactMap { $0 as? NSTextField }.first { $0 !== longCell.textField }!
        precondition(dateLabel.frame.maxY <= table.rect(ofRow: 1).height, "wrapped term and date must fit the row")
        precondition(Set(NSApp.windows.map(ObjectIdentifier.init)) == windowsBefore, "wordbook must not create another NSWindow")
        search.stringValue = "fragile"; page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        precondition(page.isShowingDetail && detail.string.contains("The glass is fragile."))
        let savedStyle = UserDefaults.standard.object(forKey: "readingStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "readingStyle") }
        let detailText = detail.string
        owner.setReadingStyle(.books)
        precondition(page.isShowingDetail && detail.string == detailText && search.stringValue == "fragile", "style switch in detail keeps the same page/content/search")
        owner.setReadingStyle(.paper)
        page.goBack()
        precondition(!page.isShowingDetail && search.stringValue == "fragile", "back to list preserves search")
        // Clicking the selected row again must still reopen it.
        _ = table.sendAction(table.action, to: table.target)
        precondition(page.isShowingDetail, "a previously selected row can be opened again")
        page.goBack(); page.goBack()
        precondition(owner.panel.contentView === owner.readingContent && !owner.showingWordbook)
        precondition(owner.question.stringValue == "My unsent question" && owner.transcript.string == "Existing reading answer")
        precondition(owner.messages.count == 1 && owner.activeGeneration == generation, "navigation cannot reset model state")
        precondition(owner.panel.frame == frame && owner.panel.windowNumber == number, "navigation preserves window identity, size and location")
        owner.openWordbook()
        owner.showWindow(reason: "repeat_selection")
        precondition(!owner.showingWordbook && owner.panel.contentView === owner.readingContent, "Books repeat gesture restores reading page")
        precondition(!events.contains { $0["event"] as? String == "request_started" }, "browsing cannot request a model")
        if let i = CommandLine.arguments.firstIndex(of: "--render-dir") {
            let output = URL(fileURLWithPath: CommandLine.arguments[i+1])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            func render(_ name: String) throws {
                let view = owner.panel.contentView!; view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            }
            PaperTheme.apply(.dark, to: owner.panel)
            owner.openWordbook()
            search.stringValue = ""; page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            try render("list")
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); try render("detail")
            page.goBack(); page.goBack(); try render("return-reading")
        }
        print("PASS: same NSWindow/frame; list-detail-list-reading; repeated row click; retained search/draft/answer/request state; real selection returns to reading; zero model requests")
    }
}
