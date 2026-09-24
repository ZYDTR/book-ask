import AppKit

extension BookAsk {
    func updateQuestionLengthHint() {
        guard let question else { return }
        if InputLengthLimit.allows(question.string),
           status?.stringValue == InputLengthLimit.rejection("追问", action: "发送") {
            status.stringValue = readyStatus
            status.toolTip = nil
        }
    }

    func updatePromptLengthHint(saving: Bool = false) {
        guard let draft = promptDraftEditor?.string else { return }
        let valid = InputLengthLimit.allows(draft)
        promptLimitLabel?.stringValue = InputLengthLimit.counter(draft)
        promptLimitLabel?.textColor = valid ? PaperTheme.muted : PaperTheme.coral
        promptLimitLabel?.toolTip = InputLengthLimit.detail(draft, field: "提示词")
        promptLimitLabel?.setAccessibilityLabel(promptLimitLabel?.toolTip)
        promptGuidanceLabel?.stringValue = valid ? "告诉 AI，你希望它怎样解释。最多 5000 字符。"
            : saving ? InputLengthLimit.rejection("提示词", action: "保存") : "超过 5000 字符，请缩短后保存。内容已保留。"
        promptGuidanceLabel?.textColor = valid ? PaperTheme.muted : PaperTheme.coral
    }

    func validateRequestInput(_ text: String, automatic: Bool) -> Bool {
        guard !InputLengthLimit.allows(text) else { return true }
        let field = automatic ? "提示词" : "追问"
        updateQuestionLengthHint()
        status.stringValue = InputLengthLimit.rejection(field, action: "发送")
        status.toolTip = InputLengthLimit.detail(text, field: field)
        return false
    }

    func updateToolbar(width: CGFloat) {
        let compact = toolbarCompact ? width < 472 : width < 452
        toolbarCompact = compact
        let popup = compact ? "弹窗" : "划词弹窗"
        let automatic = compact ? "自动发" : "自动发送"
        if popupButton.title != popup { popupButton.title = popup }
        if automaticButton.title != automatic { automaticButton.title = automatic }
        popupButton.setAccessibilityLabel("划词弹窗")
        automaticButton.setAccessibilityLabel("自动发送")
    }

    func updateExcerptSize() {
        guard let quote else { return }
        quote.readingFontSize = answerFontSize
        quote.applyStyle()
        quoteHeight?.constant = quote.excerptHeight
        updateQuestionHeight()
    }

    func showSizeFeedback() {
        sizeFeedbackWork?.cancel()
        answerSizeLabel.stringValue = " 阅读字号 \(Int(answerFontSize)) "
        answerSizeLabel.isHidden = false
        let work = DispatchWorkItem { [weak self] in self?.answerSizeLabel.isHidden = true }
        sizeFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func updatePinControl() {
        let pinned = panelController.isPinned
        (pinButton as? PaperButton)?.symbol = pinned ? "pin.fill" : "pin"
        pinButton.state = pinned ? .on : .off
        pinButton.setAccessibilityLabel(pinned ? "取消固定窗口" : "固定窗口")
        pinButton.toolTip = pinned ? "取消固定：恢复点击窗外收起；Esc 可收起" : "固定窗口：点击图书时保持打开；Esc 可收起"
        wordbook?.refreshPin(pinned)
    }

    @objc func togglePinned() {
        panelController.isPinned.toggle()
        updatePinControl()
        record(["event": "window_pin_changed", "pinned": panelController.isPinned])
    }

    @objc func showAppearancePicker() {
        let menu = NSMenu(title: "深浅色")
        for choice in ReadingAppearance.allCases {
            let item = menu.addItem(withTitle: choice.title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = choice.rawValue
            item.state = ReadingPreferences.appearance() == choice ? .on : .off
        }
        panelController.automaticDismissalSuspended = true
        defer { panelController.automaticDismissalSuspended = false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: appearanceButton.bounds.minY - 4), in: appearanceButton)
    }

    @objc func togglePromptEditor() {
        if promptExpanded { closePromptEditor(save: false); return }
        let editorPanel = AskPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        editorPanel.title = "提示词"
        editorPanel.isReleasedWhenClosed = false
        PaperTheme.window(editorPanel)
        editorPanel.appearance = panel.appearance
        let content = PaperCanvas(); editorPanel.contentView = content
        let label = NSTextField(labelWithString: "告诉 AI，你希望它怎样解释。最多 5000 字符。")
        label.font = .systemFont(ofSize: 13); label.textColor = PaperTheme.muted
        promptGuidanceLabel = label
        let (scroll, text) = ReadingTextArea.make(font: .systemFont(ofSize: 13), height: 280)
        text.isEditable = true; text.isRichText = false; text.allowsUndo = true
        PaperTheme.text(text, font: .systemFont(ofSize: 13))
        text.string = promptEditor.string
        text.delegate = self
        text.setAccessibilityLabel("编辑提示词")
        let limit = NSTextField(labelWithString: InputLengthLimit.counter(text.string))
        limit.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        promptLimitLabel = limit
        let cancel = PaperButton("取消", kind: .quiet, target: self, action: #selector(cancelPrompt))
        let save = PaperButton("保存", kind: .quiet, target: self, action: #selector(savePrompt))
        cancel.keyEquivalent = "\u{1b}"
        for view in [label, scroll, limit, cancel, save] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            scroll.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -16),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            limit.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            limit.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12),
            limit.centerYAnchor.constraint(equalTo: save.centerYAnchor)
        ])
        editorPanel.onEscape = { [weak self] in self?.closePromptEditor(save: false) }
        promptPanel = editorPanel; promptDraftEditor = text; promptExpanded = true
        updatePromptLengthHint()
        panel.beginSheet(editorPanel)
        editorPanel.makeFirstResponder(text)
    }

    @objc func cancelPrompt() { closePromptEditor(save: false) }
    @objc func savePrompt() { closePromptEditor(save: true) }

    func closePromptEditor(save: Bool) {
        guard let editorPanel = promptPanel else { return }
        if save, let draft = promptDraftEditor?.string {
            updatePromptLengthHint(saving: true)
            guard InputLengthLimit.allows(draft) else { return }
            promptEditor.string = draft
            ReadingPreferences.prompt = draft
            if activeTask == nil { status.stringValue = "提示词已保存 · 下次划选时生效" }
        }
        panel.endSheet(editorPanel); editorPanel.orderOut(nil)
        promptExpanded = false; promptPanel = nil; promptDraftEditor = nil
        promptLimitLabel = nil; promptGuidanceLabel = nil
        panel.makeFirstResponder(question)
    }
}
