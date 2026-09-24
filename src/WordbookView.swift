import AppKit

/// Keep AppKit's inset field-editor geometry while drawing only the search contents.
/// A borderless NSSearchField gives its editor the entire frame, including the icon.
private final class WordbookSearchCell: NSSearchFieldCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}

private final class WordbookSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { WordbookSearchCell.self }
        set { }
    }
}

@MainActor
final class WordbookView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = WordbookSearchField()
    private let heading = NSTextField(labelWithString: "词本")
    private let footer = NSTextField(labelWithString: "划词与问答自动保存在本机")
    private let searchRule = PaperRule()
    private let margin = PaperRule()
    private var lastRowWidth: CGFloat = 0
    private let count = NSTextField(labelWithString: "正在读取…")
    private let table = NSTableView()
    private let detail: NSTextView
    private let detailScroll: NSScrollView
    private let listScroll = ReadingScrollView()
    private var backButton: PaperButton!
    private var pinButton: PaperButton!
    private var cacheButton: PaperButton!
    private var previousButton: PaperButton!
    private var nextButton: PaperButton!
    private var deleteButton: PaperButton!
    private var undoButton: PaperButton!
    private let versionLabel = NSTextField(labelWithString: "")
    private let actionStatus = NSTextField(labelWithString: "")
    private var detailControlsTop: NSLayoutConstraint!
    private var selectedDefinition = 0
    private var detailTerm = ""
    private var deleted: DeletedDefinition?
    private var undoExpiry: DispatchWorkItem?
    private var undoTimer: Timer?
    private var undoDeadline: TimeInterval?
    private var mutating = false
    var onLibraryChanged: ((String) -> Void)?
    private var updatingSelection = false
    private(set) var isShowingDetail = false
    var onReturnToReading: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var preferredResponder: NSResponder { isShowingDetail ? detail : search }
    private var entries: [WordbookEntry] = []
    private var filtered: [WordbookEntry] = []
    private var revision = 0
    private let fallbackBook: String
    private let library: WordbookLibrary

    init(fallbackBook: String, library: WordbookLibrary = .shared) {
        self.fallbackBook = fallbackBook
        self.library = library
        let (detailScroll, detailText) = ReadingTextArea.make(font: PaperTheme.readingFont(15), height: 480)
        detail = detailText
        self.detailScroll = detailScroll
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 539))
        let content = self
        let paper = PaperCanvas(frame: bounds)
        paper.autoresizingMask = [.width, .height]
        addSubview(paper)
        backButton = PaperButton("返回阅读", kind: .quiet, symbol: "chevron.left", target: self, action: #selector(goBack))
        heading.font = .systemFont(ofSize: 21, weight: .medium)
        heading.textColor = PaperTheme.ink
        search.font = .systemFont(ofSize: 12)
        search.setAccessibilityLabel("搜索词本")
        search.delegate = self
        search.isBezeled = true; search.drawsBackground = false; search.focusRingType = .none
        search.cell?.isScrollable = true
        search.textColor = PaperTheme.ink
        footer.font = .systemFont(ofSize: 10); footer.textColor = PaperTheme.muted
        pinButton = PaperButton("", kind: .quiet, symbol: "pin", target: self, action: #selector(togglePin))
        let close = pinButton!
        refreshPin(false)
        cacheButton = PaperButton("缓存", kind: .toggle, target: self, action: #selector(toggleCache))
        cacheButton.state = ReadingPreferences.cacheEnabled ? .on : .off
        cacheButton.setAccessibilityLabel("复用已保存的解释")
        cacheButton.toolTip = "开启后复用最早保留的解释，响应更快，沿用当时的语境；关闭后每次新的划选重新解释。自动发送由阅读页的开关决定。"
        previousButton = PaperButton("上一份", kind: .quiet, symbol: "chevron.left", target: self, action: #selector(previousDefinition))
        nextButton = PaperButton("下一份", kind: .quiet, symbol: "chevron.right", target: self, action: #selector(nextDefinition))
        previousButton.setAccessibilityLabel("上一份解释"); nextButton.setAccessibilityLabel("下一份解释")
        previousButton.toolTip = "上一份解释"; nextButton.toolTip = "下一份解释"
        deleteButton = PaperButton("", kind: .quiet, symbol: "trash", target: self, action: #selector(deleteDefinition))
        deleteButton.foregroundColorOverride = .systemRed
        deleteButton.symbolPointSize = 16
        deleteButton.symbolOpacity = 1
        deleteButton.circularHover = true
        deleteButton.setAccessibilityLabel("删除这份解释及其追问")
        deleteButton.toolTip = "删除这份解释及其追问，其他解释保留；删除后可以撤销。"
        undoButton = PaperButton("撤销 10s", kind: .quiet, symbol: "arrow.uturn.backward", target: self, action: #selector(undoDelete))
        undoButton.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        undoButton.setAccessibilityLabel("撤销删除")
        undoButton.toolTip = "恢复刚刚删除的内容（删除后10秒内可用）"
        undoButton.isHidden = true
        versionLabel.font = .systemFont(ofSize: 11); versionLabel.textColor = PaperTheme.muted
        actionStatus.font = .systemFont(ofSize: 11); actionStatus.textColor = PaperTheme.muted
        actionStatus.isHidden = true
        actionStatus.lineBreakMode = .byTruncatingTail
        count.font = .systemFont(ofSize: 11)
        count.textColor = PaperTheme.muted
        count.lineBreakMode = .byTruncatingTail
        detail.setAccessibilityLabel("词本原文与解释")
        PaperTheme.text(detail, font: PaperTheme.readingFont(15), inset: NSSize(width: 16, height: 12))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("selection"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 51
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.style = .plain
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(openSelectedTerm)
        table.setAccessibilityLabel("已保存的词句")
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.hasHorizontalScroller = false
        listScroll.horizontalScrollElasticity = .none
        listScroll.documentView = table
        for view in [backButton!, heading, search, searchRule, count, footer, margin, close, listScroll, detailScroll, cacheButton!, previousButton!, nextButton!, deleteButton!, undoButton!, versionLabel, actionStatus] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        detailControlsTop = previousButton.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 14)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            close.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cacheButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            cacheButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -14),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 48),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            count.lastBaselineAnchor.constraint(equalTo: heading.lastBaselineAnchor),
            count.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: heading.trailingAnchor, constant: 12),
            search.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            search.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: count.trailingAnchor),
            search.heightAnchor.constraint(equalToConstant: 24),
            searchRule.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 5),
            searchRule.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            searchRule.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            searchRule.heightAnchor.constraint(equalToConstant: 1),
            listScroll.topAnchor.constraint(equalTo: searchRule.bottomAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            listScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            listScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            margin.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 49),
            margin.widthAnchor.constraint(equalToConstant: 1),
            margin.topAnchor.constraint(equalTo: listScroll.topAnchor),
            margin.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            detailControlsTop,
            previousButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            previousButton.widthAnchor.constraint(equalToConstant: 70),
            previousButton.heightAnchor.constraint(equalToConstant: 26),
            versionLabel.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 4),
            nextButton.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 70),
            nextButton.heightAnchor.constraint(equalToConstant: 26),
            deleteButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            deleteButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),
            actionStatus.leadingAnchor.constraint(greaterThanOrEqualTo: heading.trailingAnchor, constant: 12),
            actionStatus.centerYAnchor.constraint(equalTo: heading.centerYAnchor, constant: 2),
            actionStatus.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -4),
            undoButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            undoButton.widthAnchor.constraint(equalToConstant: 94),
            undoButton.heightAnchor.constraint(equalToConstant: 28),
            undoButton.centerYAnchor.constraint(equalTo: actionStatus.centerYAnchor),
            detailScroll.topAnchor.constraint(equalTo: previousButton.bottomAnchor, constant: 6),
            detailScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            detailScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        showList()
        refreshStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshStyle() {
        heading.textColor = PaperTheme.ink; search.textColor = PaperTheme.ink
        search.placeholderAttributedString = NSAttributedString(string: "搜索词句或解释", attributes: [.foregroundColor: PaperTheme.muted])
        count.textColor = PaperTheme.muted; footer.textColor = PaperTheme.muted
        versionLabel.textColor = PaperTheme.muted; actionStatus.textColor = PaperTheme.muted
        margin.isHidden = true
        let selectedRows = table.selectedRowIndexes
        updatingSelection = true
        table.reloadData()
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        updatingSelection = false
        if isShowingDetail { showDetail(focus: false, keepScroll: true) }
        needsDisplay = true
    }

    func refreshPin(_ pinned: Bool) {
        pinButton.symbol = pinned ? "pin.fill" : "pin"
        pinButton.state = pinned ? .on : .off
        pinButton.setAccessibilityLabel(pinned ? "取消固定窗口" : "固定窗口")
        pinButton.toolTip = pinned ? "取消固定：恢复点击窗外收起；Esc 可收起" : "固定窗口：点击图书时保持打开；Esc 可收起"
    }

    @objc private func togglePin() { onTogglePin?() }

    override func layout() {
        super.layout()
        let width = table.bounds.width
        if abs(width - lastRowWidth) > 1 {
            lastRowWidth = width
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<filtered.count))
        }
    }

    func open() {
        showList()
        reload()
    }

    @objc func goBack() {
        if isShowingDetail { showList(); window?.makeFirstResponder(search) }
        else { onReturnToReading?() }
    }

    private func showList() {
        isShowingDetail = false
        detailScroll.isHidden = true
        for view in [previousButton!, nextButton!, deleteButton!, versionLabel] { view.isHidden = true }
        for view in [heading, search, searchRule, count, footer, listScroll] { view.isHidden = false }
        count.isHidden = !actionStatus.isHidden
        backButton.title = "返回阅读"
        backButton.setAccessibilityLabel("返回阅读")
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
        count.stringValue = query.isEmpty ? "\(entries.count) 个词句" : "找到 \(filtered.count) / \(entries.count) 个词句"
        updatingSelection = true
        table.reloadData()
        if let row = filtered.firstIndex(where: { $0.id == previousID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if isShowingDetail { showDetail() }
        } else {
            table.deselectAll(nil)
            if isShowingDetail { showList() }
        }
        updatingSelection = false
        if filtered.isEmpty {
            count.stringValue = query.isEmpty ? "词本还是空的，划词后会自动保存在这里" : "没有找到匹配的词句或解释"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let string = filtered[row].selection.replacingOccurrences(of: "\n", with: " ") as NSString
        let height = string.boundingRect(with: NSSize(width: max(100, tableView.bounds.width - 60), height: 100),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: PaperTheme.serif(17)]).height
        return height > 24 ? 71 : 51
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaperTableRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = NSTableCellView()
        let title = NSTextField(wrappingLabelWithString: entry.selection.replacingOccurrences(of: "\n", with: " "))
        title.font = PaperTheme.serif(17)
        title.textColor = PaperTheme.ink
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2
        title.preferredMaxLayoutWidth = max(100, tableView.bounds.width - 60)
        let subtitle = NSTextField(labelWithString: Self.dateLabel(entry.latestTime))
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = PaperTheme.muted
        subtitle.lineBreakMode = .byTruncatingTail
        if entry.definitions.count > 1 {
            let summary = NSMutableAttributedString(string: Self.dateLabel(entry.latestTime) + " · ", attributes:
                [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: PaperTheme.muted])
            summary.append(NSAttributedString(string: "\(entry.definitions.count) 份解释", attributes:
                [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: PaperTheme.ink]))
            subtitle.attributedStringValue = summary
        }
        let trash = PaperButton("", kind: .quiet, symbol: "trash", target: self, action: #selector(deleteTermFromList(_:)))
        trash.identifier = NSUserInterfaceItemIdentifier(entry.id)
        trash.foregroundColorOverride = .systemRed
        trash.symbolPointSize = 16
        trash.symbolOpacity = 1
        trash.circularHover = true
        trash.isEnabled = !mutating
        trash.setAccessibilityLabel("删除词条：\(entry.selection)")
        trash.toolTip = "删除整个词条及其全部解释、追问；删除后可以撤销。"
        for view in [title, subtitle, trash] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        cell.textField = title
        cell.toolTip = entry.definitions.count > 1 ? "共 \(entry.definitions.count) 份解释，点开后切换查看。\n" + entry.selection : entry.selection
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: trash.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            trash.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            trash.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
            trash.widthAnchor.constraint(equalToConstant: 32),
            trash.heightAnchor.constraint(equalToConstant: 32)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !updatingSelection { showDetail() }
    }

    @objc private func openSelectedTerm() { showDetail() }

    private func showDetail(focus: Bool = true, keepScroll: Bool = false) {
        let previousPoint = detailScroll.contentView.bounds.origin
        guard filtered.indices.contains(table.selectedRow) else { return }
        let source = filtered[table.selectedRow]
        if detailTerm != source.id { selectedDefinition = 0; detailTerm = source.id }
        selectedDefinition = min(selectedDefinition, max(0, source.definitions.count - 1))
        let selectedID = source.definitions.indices.contains(selectedDefinition) ? source.definitions[selectedDefinition].id : nil
        let entry = source.displaying(selectedID)
        for view in [previousButton!, nextButton!, deleteButton!, versionLabel] { view.isHidden = false }
        previousButton.isEnabled = selectedDefinition > 0 && !mutating
        nextButton.isEnabled = selectedDefinition + 1 < source.definitions.count && !mutating
        deleteButton.isEnabled = !mutating
        versionLabel.stringValue = source.definitions.isEmpty ? "尚无解释" : "第 \(selectedDefinition + 1) / \(source.definitions.count) 份"
        isShowingDetail = true
        detailScroll.isHidden = false
        for view in [heading, search, searchRule, count, footer, listScroll] { view.isHidden = true }
        backButton.title = "返回词本"
        backButton.setAccessibilityLabel("返回词本")
        let text = NSMutableAttributedString()
        func append(_ value: String, font: NSFont, color: NSColor = PaperTheme.ink) {
            text.append(NSAttributedString(string: value + "\n\n", attributes:
                [.font: font, .foregroundColor: color, .paragraphStyle: PaperTheme.paragraph()]))
        }
        append(entry.selection, font: PaperTheme.serif(23))
        let date = entry.definitions.first?.createdAt ?? entry.latestTime
        append(entry.book + " · " + Self.dateLabel(date), font: .systemFont(ofSize: 11, weight: .medium), color: PaperTheme.muted)
        for (index, exchange) in entry.exchanges.enumerated() {
            if index > 0 && !exchange.question.isEmpty {
                append("提问：\(exchange.question)", font: PaperTheme.readingFont(13), color: PaperTheme.coral)
            } else if index == 0 {
                append("释义与例句", font: .systemFont(ofSize: 10, weight: .medium), color: PaperTheme.muted)
            }
            append(exchange.answer, font: PaperTheme.readingFont(15))
        }
        if let saved = entry.definitions.first, !saved.contextText.isEmpty {
            append("当时的语境", font: .systemFont(ofSize: 10, weight: .medium), color: PaperTheme.muted)
            append(saved.contextText, font: PaperTheme.readingFont(13), color: PaperTheme.muted)
        }
        if !entry.status.isEmpty { append(entry.status, font: .systemFont(ofSize: 11), color: PaperTheme.muted) }
        PaperTheme.compactParagraphBreaks(text)
        detail.textStorage?.setAttributedString(text)
        detail.textColor = PaperTheme.ink
        detail.selectedTextAttributes = [.backgroundColor: PaperTheme.blue.withAlphaComponent(0.35), .foregroundColor: PaperTheme.ink]
        // Setting textColor globally would flatten the conversation's role colors.
        detail.textStorage?.setAttributedString(text)
        if keepScroll {
            detailScroll.contentView.scroll(to: previousPoint)
            detailScroll.reflectScrolledClipView(detailScroll.contentView)
        } else { detail.scrollToBeginningOfDocument(nil) }
        if focus { window?.makeFirstResponder(detail) }
    }

    @objc private func toggleCache() {
        ReadingPreferences.cacheEnabled.toggle()
        cacheButton.state = ReadingPreferences.cacheEnabled ? .on : .off
    }
    @objc private func previousDefinition() { selectedDefinition = max(0, selectedDefinition - 1); showDetail() }
    @objc private func nextDefinition() { selectedDefinition += 1; showDetail() }
    @objc func deleteDefinition() {
        guard !mutating, isShowingDetail, filtered.indices.contains(table.selectedRow) else { return }
        let source = filtered[table.selectedRow]
        let id = source.definitions.indices.contains(selectedDefinition) ? source.definitions[selectedDefinition].id : nil
        delete(source.id, definitionID: id, entireTerm: false)
    }
    @objc func deleteTermFromList(_ sender: NSButton) {
        guard !isShowingDetail, let term = sender.identifier?.rawValue, filtered.contains(where: { $0.id == term }) else { return }
        delete(term, definitionID: nil, entireTerm: true)
    }
    private func showFeedback(_ message: String, canUndo: Bool, help: String? = nil) {
        actionStatus.stringValue = message
        actionStatus.toolTip = help
        let visible = !message.isEmpty
        actionStatus.isHidden = !visible
        undoButton.isHidden = !visible || !canUndo
        count.isHidden = isShowingDetail || visible
        detailControlsTop.constant = visible ? 42 : 14
        needsLayout = true
    }

    private func clearFeedback(after seconds: TimeInterval) {
        undoExpiry?.cancel()
        undoTimer?.invalidate(); undoTimer = nil
        undoDeadline = nil
        let work = DispatchWorkItem { [weak self] in
            self?.deleted = nil
            self?.showFeedback("", canUndo: false)
        }
        undoExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func startUndoCountdown() {
        undoExpiry?.cancel(); undoTimer?.invalidate()
        undoDeadline = ProcessInfo.processInfo.systemUptime + 10
        updateUndoCountdown()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.updateUndoCountdown()
            }
        }
        undoTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateUndoCountdown() {
        guard let deadline = undoDeadline else { return }
        let remaining = max(0, Int(ceil(deadline - ProcessInfo.processInfo.systemUptime)))
        if remaining == 0 {
            undoTimer?.invalidate(); undoTimer = nil; undoDeadline = nil; deleted = nil
            showFeedback("", canUndo: false)
        } else {
            undoButton.title = "撤销 \(remaining)s"
            undoButton.setAccessibilityLabel("撤销删除，剩余 \(remaining) 秒")
        }
    }

    private func delete(_ term: String, definitionID: String?, entireTerm: Bool) {
        guard !mutating else { return }
        mutating = true; deleteButton.isEnabled = false; undoButton.isEnabled = false
        Task { @MainActor in
            defer { mutating = false; deleteButton.isEnabled = true; undoButton.isEnabled = true }
            do {
                let token = try await (entireTerm ? library.deleteTerm(term) : library.delete(term, definitionID: definitionID))
                deleted = token; undoExpiry?.cancel()
                showFeedback(entireTerm ? "已删除词条" : "已删除这份解释", canUndo: true, help: term)
                startUndoCountdown()
                onLibraryChanged?(term); reload()
            } catch { showFeedback("删除失败，内容已保留", canUndo: deleted != nil, help: error.localizedDescription) }
        }
    }
    @objc func undoDelete() {
        updateUndoCountdown()
        guard !mutating, let token = deleted else { return }
        mutating = true; undoButton.isEnabled = false; undoExpiry?.cancel()
        undoTimer?.invalidate(); undoTimer = nil; undoDeadline = nil
        Task { @MainActor in
            defer { mutating = false; undoButton.isEnabled = true }
            do {
                try await library.undo(token); deleted = nil
                showFeedback("已恢复", canUndo: false)
                clearFeedback(after: 3)
                onLibraryChanged?(token.term); reload()
            } catch {
                undoButton.title = "重试撤销"; undoButton.setAccessibilityLabel("重试撤销删除")
                showFeedback("恢复失败", canUndo: true, help: error.localizedDescription)
            }
        }
    }

    private static func dateLabel(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
