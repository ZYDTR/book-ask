import AppKit

@MainActor
final class WordbookWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let count = NSTextField(labelWithString: "正在读取…")
    private let table = NSTableView()
    private let detail: NSTextView
    private var entries: [WordbookEntry] = []
    private var filtered: [WordbookEntry] = []
    private var revision = 0
    private let fallbackBook: String
    private let library: WordbookLibrary

    init(fallbackBook: String, library: WordbookLibrary = .shared) {
        self.fallbackBook = fallbackBook
        self.library = library
        let (detailScroll, detailText) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 480)
        detail = detailText
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "词本"
        window.minSize = NSSize(width: 640, height: 450)
        window.isReleasedWhenClosed = false
        PaperTheme.window(window)
        window.setFrameAutosaveName("BookAskWordbook")
        super.init(window: window)
        window.center()
        let content = window.contentView!
        let paper = PaperCanvas(frame: content.bounds)
        paper.autoresizingMask = [.width, .height]
        content.addSubview(paper)
        search.placeholderString = "搜索词句或解释"
        search.font = .systemFont(ofSize: 12)
        search.setAccessibilityLabel("搜索词本")
        search.delegate = self
        count.font = .systemFont(ofSize: 11)
        count.textColor = PaperTheme.muted
        count.lineBreakMode = .byTruncatingTail
        detail.setAccessibilityLabel("词本原文与解释")
        PaperTheme.text(detail, font: .systemFont(ofSize: 15), inset: NSSize(width: 16, height: 12))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("selection"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 64
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.style = .plain
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("已保存的词句")
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.hasHorizontalScroller = false
        listScroll.horizontalScrollElasticity = .none
        listScroll.documentView = table
        let divider = NSBox()
        divider.boxType = .custom
        divider.fillColor = PaperTheme.line
        divider.borderWidth = 0
        divider.setContentHuggingPriority(.defaultLow, for: .vertical)
        for view in [search, count, listScroll, divider, detailScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.widthAnchor.constraint(equalToConstant: 232),
            count.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: search.trailingAnchor, constant: 18),
            count.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            listScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            listScroll.widthAnchor.constraint(equalToConstant: 248),
            listScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            divider.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 4),
            divider.topAnchor.constraint(equalTo: listScroll.topAnchor),
            divider.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            detailScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            detailScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor)
        ])
        window.setContentSize(NSSize(width: 800, height: 560))
        content.layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func open() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    func reload() {
        revision += 1
        let current = revision
        let book = fallbackBook
        Task {
            let result: Result<[WordbookEntry], Error>
            do { result = .success(try await library.entries(fallbackBook: book)) }
            catch { result = .failure(error) }
            guard current == revision else { return }
            switch result {
            case .success(let values): entries = values; applyFilter()
            case .failure:
                count.stringValue = "读取失败"
                detail.string = "暂时无法读取本地词本，请关闭后重新打开。"
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    private func applyFilter() {
        let previousID = filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow].id : nil
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = entries.filter { $0.matches(query) }
        count.stringValue = query.isEmpty ? "\(entries.count) 个词句 · 划词与问答自动保存在本机" : "找到 \(filtered.count) / \(entries.count) 个词句"
        table.reloadData()
        if !filtered.isEmpty {
            let row = filtered.firstIndex { $0.id == previousID } ?? 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            showDetail()
        } else {
            detail.string = query.isEmpty ? "词本还是空的。\n\n在图书中划过的词句和对应回答会自动保存在这里。" : "没有找到匹配的词句或解释。"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaperTableRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: entry.selection.replacingOccurrences(of: "\n", with: " "))
        title.font = PaperTheme.serif(15)
        title.textColor = PaperTheme.ink
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: Self.dateLabel(entry.latestTime))
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = PaperTheme.muted
        subtitle.lineBreakMode = .byTruncatingTail
        for view in [title, subtitle] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        cell.textField = title
        cell.toolTip = entry.selection
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 12),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { showDetail() }

    private func showDetail() {
        guard filtered.indices.contains(table.selectedRow) else { return }
        let entry = filtered[table.selectedRow]
        let text = NSMutableAttributedString()
        func append(_ value: String, font: NSFont, color: NSColor = PaperTheme.ink) {
            text.append(NSAttributedString(string: value + "\n\n", attributes:
                [.font: font, .foregroundColor: color, .paragraphStyle: PaperTheme.paragraph()]))
        }
        append(entry.selection, font: PaperTheme.serif(23))
        append(entry.book, font: .systemFont(ofSize: 11, weight: .medium), color: PaperTheme.muted)
        for (index, exchange) in entry.exchanges.enumerated() {
            if index > 0 && !exchange.question.isEmpty {
                append("提问：\(exchange.question)", font: .systemFont(ofSize: 13, weight: .medium), color: PaperTheme.coral)
            } else if index == 0 {
                append("释义与例句", font: .systemFont(ofSize: 10, weight: .medium), color: PaperTheme.muted)
            }
            append(exchange.answer, font: .systemFont(ofSize: 15))
        }
        if !entry.status.isEmpty { append(entry.status, font: .systemFont(ofSize: 11), color: PaperTheme.muted) }
        detail.textStorage?.setAttributedString(text)
        detail.scrollToBeginningOfDocument(nil)
    }

    private static func dateLabel(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
