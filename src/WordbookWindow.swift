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

    init(fallbackBook: String) {
        self.fallbackBook = fallbackBook
        let (detailScroll, detailText) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 480)
        detail = detailText
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "词本"
        window.minSize = NSSize(width: 640, height: 450)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("BookAskWordbook")
        super.init(window: window)
        window.center()
        let content = window.contentView!
        search.placeholderString = "搜索词句或解释"
        search.setAccessibilityLabel("搜索词本")
        search.delegate = self
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        count.lineBreakMode = .byTruncatingTail
        detail.setAccessibilityLabel("词本原文与解释")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("selection"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 53
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("已保存的词句")
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.hasHorizontalScroller = false
        listScroll.horizontalScrollElasticity = .none
        listScroll.documentView = table
        let divider = NSBox()
        divider.boxType = .separator
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
            let result = await Task.detached(priority: .userInitiated) { Result { try WordbookStore.load(fallbackBook: book) } }.value
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: entry.selection.replacingOccurrences(of: "\n", with: " "))
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: "\(Self.dateLabel(entry.latestTime)) · \(entry.visits.count) 次划词")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        for view in [title, subtitle] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        cell.textField = title
        cell.toolTip = entry.selection
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
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
        var blocks = [entry.selection, entry.book]
        for visit in entry.visits {
            blocks.append(Self.dateLabel(visit.time))
            for (index, exchange) in visit.exchanges.enumerated() {
                if !exchange.automatic && !exchange.question.isEmpty { blocks.append("提问：\(exchange.question)") }
                else if index == 0 { blocks.append("解释") }
                blocks.append(exchange.answer)
            }
            if !visit.status.isEmpty { blocks.append(visit.status) }
        }
        detail.string = blocks.joined(separator: "\n\n")
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
