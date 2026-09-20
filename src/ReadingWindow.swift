import AppKit

/// Presentation stays separate from capture, clipboard and model state.
extension BookAsk {
    func buildWindow() {
        panel = AskPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 511),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "读书提问"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 500, height: 539)
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.setFrameAutosaveName("BookAskPanel")
        panel.setFrameUsingName("BookAskPanel")
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: 500, height: 539)), display: false)
        PaperTheme.window(panel)
        let content = PaperCanvas()
        panel.contentView = content
        panelController = ReadingPanelController(panel: panel, automaticDismissal: ReadingPreferences.autoDismiss,
            record: { [weak self] fields in self?.record(fields) })

        automaticButton = PaperButton("自动解释", kind: .toggle, target: self, action: #selector(toggleAutomatic))
        automaticButton.state = autoExplain ? .on : .off
        autoDismissButton = PaperButton("15 秒后收起", kind: .toggle, target: self, action: #selector(toggleAutoDismiss))
        autoDismissButton.setAccessibilityLabel("15 秒后自动收起")
        autoDismissButton.state = ReadingPreferences.autoDismiss ? .on : .off
        autoDismissButton.toolTip = "查词弹出 15 秒后收起；在窗口内点击、输入或滚动会取消本次计时"
        promptDisclosure = PaperButton("编辑提示词", kind: .quiet, symbol: "slider.horizontal.3", target: self, action: #selector(togglePromptEditor))
        promptDisclosure.toolTip = "编辑自动解释提示词，修改后自动保存"
        let wordbookButton = PaperButton("词本", kind: .quiet, symbol: "book.closed", target: self, action: #selector(openWordbook))
        wordbookButton.toolTip = "查看已保存的词句与解释"

        let (editorScroll, editor) = ReadingTextArea.make(font: .systemFont(ofSize: 12), height: 100)
        promptScroll = editorScroll; promptEditor = editor
        PaperTheme.text(editor, font: .systemFont(ofSize: 12))
        editor.isEditable = true; editor.isRichText = false; editor.allowsUndo = true
        editor.string = ReadingPreferences.prompt
        editor.setAccessibilityLabel("自动解释提示词")
        editor.delegate = self
        promptScroll.drawsBackground = true
        promptScroll.backgroundColor = PaperTheme.blue.withAlphaComponent(0.10)
        promptScroll.wantsLayer = true; promptScroll.layer?.cornerRadius = 8
        promptScroll.isHidden = true
        promptHeight = promptScroll.heightAnchor.constraint(equalToConstant: 0)

        contextLabel = NSTextField(labelWithString: "在图书里，划选一个想读懂的词句")
        contextLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        contextLabel.textColor = PaperTheme.muted
        contextLabel.lineBreakMode = .byTruncatingTail
        let quoteWell = PigmentWell()
        let (quoteScroll, quoteView) = ReadingTextArea.make(font: PaperTheme.serif(20), height: 76)
        quote = quoteView
        PaperTheme.text(quote, font: PaperTheme.serif(20), inset: NSSize(width: 12, height: 10))
        quote.setAccessibilityLabel("选中的原文")
        quote.string = "选一句，读懂一点。"

        let section = NSTextField(labelWithString: "理解与例句")
        section.font = .systemFont(ofSize: 10.5, weight: .medium)
        section.textColor = PaperTheme.muted
        let sectionWash = PigmentWell()
        sectionWash.pigment = PaperTheme.blue; sectionWash.opacity = 0.15
        let (chatScroll, chatView) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 220)
        transcript = chatView
        PaperTheme.text(transcript, font: .systemFont(ofSize: 15), inset: NSSize(width: 0, height: 8))
        transcript.setAccessibilityLabel("AI 回答与对话")
        transcript.string = "解释与例句会出现在这里。\n\n遇到不明白的地方，可以接着问。"

        let input = PaperInputWell()
        question = NSTextField()
        question.isBordered = false; question.drawsBackground = false
        question.font = .systemFont(ofSize: 13)
        question.textColor = PaperTheme.ink
        question.placeholderAttributedString = NSAttributedString(string: "继续问一句…", attributes: [.foregroundColor: PaperTheme.muted.withAlphaComponent(0.8)])
        question.toolTip = "输入问题；留空时发送当前提示词"
        question.focusRingType = .none
        question.delegate = self; question.target = self; question.action = #selector(sendQuestion)
        question.setAccessibilityLabel("继续提问")
        sendButton = PaperButton("发送", kind: .primary, target: self, action: #selector(sendOrStop))
        sendButton.font = .systemFont(ofSize: 12, weight: .medium)
        for view in [question!, sendButton!] { view.translatesAutoresizingMaskIntoConstraints = false; input.addSubview(view) }
        status = NSTextField(labelWithString: "准备就绪")
        status.font = .systemFont(ofSize: 10)
        status.textColor = PaperTheme.muted
        status.lineBreakMode = .byTruncatingTail
        for view in [automaticButton!, autoDismissButton!, wordbookButton, promptDisclosure!, promptScroll!,
                     contextLabel!, quoteWell, quoteScroll, sectionWash, section, chatScroll, input, status!] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            automaticButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),
            automaticButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            autoDismissButton.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            autoDismissButton.leadingAnchor.constraint(equalTo: automaticButton.trailingAnchor, constant: 6),
            promptDisclosure.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            promptDisclosure.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            wordbookButton.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            wordbookButton.trailingAnchor.constraint(equalTo: promptDisclosure.leadingAnchor, constant: -2),
            wordbookButton.leadingAnchor.constraint(greaterThanOrEqualTo: autoDismissButton.trailingAnchor, constant: 8),
            promptScroll.topAnchor.constraint(equalTo: automaticButton.bottomAnchor, constant: 8),
            promptScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            promptScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), promptHeight,
            contextLabel.topAnchor.constraint(equalTo: promptScroll.bottomAnchor, constant: 11),
            contextLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            contextLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            quoteWell.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),
            quoteWell.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            quoteWell.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            quoteWell.heightAnchor.constraint(equalToConstant: 82),
            quoteScroll.topAnchor.constraint(equalTo: quoteWell.topAnchor, constant: 3),
            quoteScroll.bottomAnchor.constraint(equalTo: quoteWell.bottomAnchor, constant: -3),
            quoteScroll.leadingAnchor.constraint(equalTo: quoteWell.leadingAnchor, constant: 3),
            quoteScroll.trailingAnchor.constraint(equalTo: quoteWell.trailingAnchor, constant: -3),
            section.topAnchor.constraint(equalTo: quoteWell.bottomAnchor, constant: 16),
            section.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 29),
            sectionWash.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: -4),
            sectionWash.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: 5),
            sectionWash.centerYAnchor.constraint(equalTo: section.centerYAnchor),
            sectionWash.heightAnchor.constraint(equalToConstant: 19),
            chatScroll.topAnchor.constraint(equalTo: section.bottomAnchor, constant: 3),
            chatScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            chatScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            chatScroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -12),
            input.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            input.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            input.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -9),
            input.heightAnchor.constraint(equalToConstant: 46),
            question.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 13),
            question.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            question.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            sendButton.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: -7),
            sendButton.centerYAnchor.constraint(equalTo: input.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 56),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 29),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }
}
