import AppKit

@main struct DefinitionVisualTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("definition-visual-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let library = WordbookLibrary(url: root.appendingPathComponent("wordbook.json"), historyURL: root.appendingPathComponent("history.jsonl"))
        var entry = try await library.appendDefinition("bank", book: "River Stories", contextText: "They sat on the river bank and watched the boats go past.", contextStatus: "Current context", exchange: .init(question: "Explain", answer: "The land beside a river.\n\nWe had lunch on the bank.", automatic: true), time: "2026-09-24T08:00:00Z")
        entry = try await library.appendDefinition("bank", book: "A Different Book", contextText: "She went to the bank to withdraw some money.", contextStatus: "Current context", exchange: .init(question: "Explain", answer: "A place that keeps and lends money.\n\nThe bank opens at nine.", automatic: true), time: "2026-09-24T08:01:00Z")
        let owner = BookAsk(); owner.buildWindow(); owner.wordbookLibrary = library
        owner.recordSink = { _ in }; owner.windowPresenter = { _ in }
        owner.panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        owner.selectedText = "bank"; owner.quote.string = "bank"; owner.currentWordbookEntry = entry
        owner.restoreWordbook(entry)
        let savedStyle = UserDefaults.standard.object(forKey: "readingStyle")
        defer { UserDefaults.standard.set(savedStyle, forKey: "readingStyle") }
        func render(_ name: String) throws {
            let view = owner.panel.contentView!; view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            precondition(abs(view.frame.width - owner.panel.frame.width) < 1, "controls must not expand the window")
            let buttons = view.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden }
            for button in buttons { precondition(view.bounds.contains(button.frame), "visible control must fit") }
        }
        for style: ReadingStyle in [.books, .paper] {
            owner.setReadingStyle(style)
            for appearance: ReadingAppearance in [.light, .dark] {
                PaperTheme.apply(appearance, to: owner.panel)
                for size in [NSSize(width: 360, height: 340), NSSize(width: 500, height: 539)] {
                    owner.panel.setContentSize(size)
                    owner.returnToReading()
                    owner.restoreWordbook(entry)
                    let label = "\(style.rawValue)-\(appearance.rawValue)-\(Int(size.width))"
                    try render(label + "-reading")
                    precondition(owner.quote.frame.maxX <= owner.addExplanationButton.frame.minX, "plus cannot cover two-line original")
                    owner.openWordbook()
                    let page = owner.wordbook!
                    let table = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTableView }.first!
                    while table.numberOfRows == 0 { await Task.yield() }
                    try render(label + "-list")
                    let row = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
                    precondition(row.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("2 份解释") },
                                 "multiple saved definitions are discoverable without opening the term")
                    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    _ = table.sendAction(table.action, to: table.target)
                    precondition(page.isShowingDetail)
                    try render(label + "-detail")
                    let next = page.subviews.compactMap { $0 as? PaperButton }.first { $0.title == "下一份" }!
                    let previous = page.subviews.compactMap { $0 as? PaperButton }.first { $0.title == "上一份" }!
                    let detail = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTextView }.first!
                    _ = next.sendAction(next.action, to: next.target)
                    precondition(detail.string.contains("A Different Book") && detail.string.contains("keeps and lends money"))
                    try render(label + "-second-definition")
                    _ = previous.sendAction(previous.action, to: previous.target)
                    precondition(detail.string.contains("River Stories") && detail.string.contains("land beside a river"))
                    page.goBack()
                }
            }
        }
        // Actual delete/undo actions on disposable data, with the empty-list case.
        owner.openWordbook(); let page = owner.wordbook!
        let table = page.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTableView }.first!
        while table.numberOfRows == 0 { await Task.yield() }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    _ = table.sendAction(table.action, to: table.target)
                    precondition(page.isShowingDetail)
        page.deleteDefinition()
        while (try await library.lookup("bank", fallbackBook: ""))?.definitions.count == 2 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        try render("after-delete")
        page.undoDelete()
        while (try await library.lookup("bank", fallbackBook: ""))?.definitions.count == 1 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        page.goBack()
        owner.panel.contentView!.layoutSubtreeIfNeeded()
        let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
        let trash = cell.subviews.compactMap { $0 as? PaperButton }.first { $0.symbol == "trash" }!
        precondition(trash.foregroundColorOverride == NSColor.systemRed && !page.isShowingDetail)
        _ = trash.sendAction(trash.action, to: trash.target)
        let deletionDeadline = Date().addingTimeInterval(5)
        while (try await library.lookup("bank", fallbackBook: "")) != nil && Date() < deletionDeadline { await Task.yield() }
        let afterListDelete = try await library.lookup("bank", fallbackBook: "")
        precondition(afterListDelete == nil)
        for _ in 0..<20 { await Task.yield() }
        precondition(!page.isShowingDetail, "list trash must not navigate into the term")
        try render("after-list-delete")
        page.undoDelete()
        let undoDeadline = Date().addingTimeInterval(5)
        while (try await library.lookup("bank", fallbackBook: "")) == nil && Date() < undoDeadline { await Task.yield() }
        let restored = try await library.lookup("bank", fallbackBook: "")
        precondition(restored?.definitions.count == 2, "list undo restores every definition")
        // Inline feedback must fit the smallest window without shifting the list.
        owner.panel.setContentSize(NSSize(width: 360, height: 340))
        for style: ReadingStyle in [.books, .paper] {
            ReadingPreferences.setStyle(style); page.refreshStyle()
            for appearance: ReadingAppearance in [.light, .dark] {
                PaperTheme.apply(appearance, to: owner.panel)
                for _ in 0..<20 { await Task.yield() }
                page.layoutSubtreeIfNeeded()
                let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
                let trash = cell.subviews.compactMap { $0 as? PaperButton }.first { $0.symbol == "trash" }!
                _ = trash.sendAction(trash.action, to: trash.target)
                let deadline = Date().addingTimeInterval(5)
                while (try await library.lookup("bank", fallbackBook: "")) != nil && Date() < deadline { await Task.yield() }
                for _ in 0..<20 { await Task.yield() }
                try render("feedback-" + style.rawValue + "-" + appearance.rawValue)
                let undo = page.subviews.compactMap { $0 as? PaperButton }.first { $0.title.hasPrefix("撤销 ") }!
                let status = page.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "已删除词条" }!
                precondition(!undo.isHidden && !status.isHidden && page.bounds.contains(undo.frame))
                precondition(undo.frame.midY > page.bounds.height * 0.7, "undo is near the top")
                precondition(status.frame.maxX <= undo.frame.minX && status.intrinsicContentSize.width <= status.frame.width)
                let scroll = table.enclosingScrollView!
                precondition(scroll.frame.maxY < undo.frame.minY, "feedback cannot cover the list")
                _ = undo.sendAction(undo.action, to: undo.target)
                let restoreDeadline = Date().addingTimeInterval(5)
                while (try await library.lookup("bank", fallbackBook: "")) == nil && Date() < restoreDeadline { await Task.yield() }
                for _ in 0..<20 { await Task.yield() }
                let restoredEntry = try await library.lookup("bank", fallbackBook: "")
                precondition(restoredEntry?.definitions.count == 2)
            }
        }
        try await Task.sleep(nanoseconds: 3_200_000_000)
        page.layoutSubtreeIfNeeded()
        let clearStatus = page.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.map(\.stringValue)
        precondition(!clearStatus.contains("已恢复"), "restored feedback clears itself")
        let fullListHeight = table.enclosingScrollView!.frame.height
        let cellAfterUndo = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
        let finalTrash = cellAfterUndo.subviews.compactMap { $0 as? PaperButton }.first { $0.symbol == "trash" }!
        _ = finalTrash.sendAction(finalTrash.action, to: finalTrash.target)
        try await Task.sleep(nanoseconds: 200_000_000)
        page.layoutSubtreeIfNeeded()
        precondition(abs(table.enclosingScrollView!.frame.height - fullListHeight) < 1, "deletion feedback never shifts the list")
        let countdown = page.subviews.compactMap { $0 as? PaperButton }.first { $0.title.hasPrefix("撤销 ") }!
        precondition(countdown.title == "撤销 10s")
        try await Task.sleep(nanoseconds: 1_100_000_000)
        precondition(countdown.title == "撤销 9s", "countdown reflects elapsed time")
        try render("countdown-nine-seconds")
        try await Task.sleep(nanoseconds: 9_000_000_000)
        page.layoutSubtreeIfNeeded()
        precondition(countdown.isHidden && abs(table.enclosingScrollView!.frame.height - fullListHeight) < 1, "expired feedback disappears without layout shift")
        page.undoDelete()
        let expired = try await library.lookup("bank", fallbackBook: "")
        precondition(expired == nil, "expired Undo cannot silently restore a term")
        print("PASS: native component render in 4 themes at 360x340/500x539, plus containment, cache/list/detail controls, actual delete/undo on isolated data")
    }
}
