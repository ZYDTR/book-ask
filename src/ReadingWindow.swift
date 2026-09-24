import AppKit

/// A fixed two-line excerpt on a pigment wash. The full original stays in text
/// storage; truncation is presentation-only and cannot alter model/cache input.
final class ReadingSelectionTextView: NSTextView {
    static let lineHeight: CGFloat = 26
    var readingFontSize: Double = 17
    var excerptLineHeight: CGFloat { ceil(readingFontSize * 1.5) }
    var excerptHeight: CGFloat { excerptLineHeight * 2 + 20 }
    static let selectionHeight: CGFloat = lineHeight * 2 + 20

    override var string: String {
        get { super.string }
        set { super.string = newValue; applyStyle() }
    }

    func applyStyle() {
        PaperTheme.text(self, font: PaperTheme.serif(readingFontSize), inset: NSSize(width: 13, height: 10))
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = true
        textContainer?.maximumNumberOfLines = 2
        textContainer?.lineBreakMode = .byTruncatingTail
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = excerptLineHeight
        paragraph.maximumLineHeight = excerptLineHeight
        defaultParagraphStyle = paragraph
        typingAttributes[.paragraphStyle] = paragraph
        textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                 range: NSRange(location: 0, length: textStorage?.length ?? 0))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if PaperTheme.style == .paper {
            PaperTheme.wash(in: bounds.insetBy(dx: 1, dy: 1), color: PaperTheme.sage, opacity: 0.14)
        }
        super.draw(dirtyRect)
    }
}

/// Presentation stays separate from capture, clipboard and model state.
extension BookAsk {
    func buildWindow() {
        panel = AskPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 539),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "读书提问"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 340)
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) {
            panel.collectionBehavior.insert(.canJoinAllApplications)
        }
        // Explicit opens restore the whole frame; fresh selections may still reposition it.
        panel.setFrameAutosaveName("BookAskPanel")
        hasWindowPosition = panel.setFrameUsingName("BookAskPanel")
        PaperTheme.window(panel)
        let content = PaperCanvas()
        readingContent = content
        panel.contentView = content
        panelController = ReadingPanelController(panel: panel, record: { [weak self] fields in self?.record(fields) })

        popupButton = PaperButton("划词弹窗", kind: .toggle, target: self, action: #selector(toggleAutomaticPopup))
        popupButton.state = autoPopup ? .on : .off
        popupButton.toolTip = "开启时划词直接打开；关闭时点鼠标旁的「问 AI」打开"
        automaticButton = PaperButton("自动发送", kind: .toggle, target: self, action: #selector(toggleAutomatic))
        automaticButton.state = autoExplain ? .on : .off
        automaticButton.toolTip = "开启时，划词打开窗口后自动发送选中文字；关闭时，点发送才会提问"
        smallerAnswerButton = PaperButton("A−", kind: .quiet, target: self, action: #selector(decreaseAnswerSize))
        largerAnswerButton = PaperButton("A+", kind: .quiet, target: self, action: #selector(increaseAnswerSize))
        smallerAnswerButton.setAccessibilityLabel("缩小阅读字号")
        largerAnswerButton.setAccessibilityLabel("放大阅读字号")
        answerSizeLabel = NSTextField(labelWithString: "")
        answerSizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        answerSizeLabel.textColor = PaperTheme.muted
        answerSizeLabel.alignment = .center
        updateAnswerSizeControls()
        promptDisclosure = PaperButton("提示词", kind: .quiet, target: self, action: #selector(togglePromptEditor))
        promptDisclosure.setAccessibilityLabel("编辑提示词")
        promptDisclosure.toolTip = "编辑 AI 如何解释你选中的文字"
        styleButton = PaperButton("", kind: .quiet, target: self, action: #selector(toggleReadingStyle))
        let wordbookButton = PaperButton("", kind: .quiet, symbol: "book", target: self, action: #selector(openWordbook))
        wordbookButton.toolTip = "词本 · 回看保存过的词句与解释"
        wordbookButton.setAccessibilityLabel("词本")
        appearanceButton = PaperButton("", kind: .quiet, symbol: "circle.lefthalf.filled", target: self, action: #selector(showAppearancePicker))
        appearanceButton.setAccessibilityLabel("深浅色")
        appearanceButton.toolTip = "选择浅色、深色或跟随系统，记住上次选择"
        pinButton = PaperButton("", kind: .quiet, symbol: "pin", target: self, action: #selector(togglePinned))
        updatePinControl()
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal; toolbar.alignment = .centerY; toolbar.spacing = 2
        let spacer = NSView()
        let buttons = [popupButton!, automaticButton!, smallerAnswerButton!, largerAnswerButton!, wordbookButton,
                       appearanceButton!, styleButton!, promptDisclosure!, pinButton!]
        for button in buttons {
            (button as? PaperButton)?.toolbarSizing = true
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .horizontal)
        }
        for button in [smallerAnswerButton!, largerAnswerButton!] {
            (button as? PaperButton)?.subduedUntilHover = true
            button.font = .systemFont(ofSize: 13, weight: .medium)
        }
        for view in [popupButton!, automaticButton!, smallerAnswerButton!, largerAnswerButton!, spacer, wordbookButton,
                     appearanceButton!, styleButton!, promptDisclosure!, pinButton!] { toolbar.addArrangedSubview(view) }
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        answerSizeLabel.isHidden = true
        answerSizeLabel.stringValue = ""
        answerSizeLabel.drawsBackground = false
        answerSizeLabel.font = .systemFont(ofSize: 11)

        let (editorScroll, editor) = ReadingTextArea.make(font: .systemFont(ofSize: 12), height: 100)
        promptScroll = editorScroll; promptEditor = editor
        PaperTheme.text(editor, font: .systemFont(ofSize: 12))
        editor.isEditable = true; editor.isRichText = false; editor.allowsUndo = true
        editor.string = ReadingPreferences.prompt
        editor.setAccessibilityLabel("自动解释提示词"); editor.delegate = self
        promptScroll.drawsBackground = true
        promptScroll.backgroundColor = PaperTheme.blue.withAlphaComponent(0.10)
        promptScroll.wantsLayer = true; promptScroll.layer?.cornerRadius = 8
        promptScroll.isHidden = true
        promptHeight = promptScroll.heightAnchor.constraint(equalToConstant: 0)

        contextLabel = NSTextField(labelWithString: "在图书里，划选一个想读懂的词句")
        contextLabel.font = .systemFont(ofSize: 10.5)
        contextLabel.textColor = PaperTheme.muted
        contextLabel.lineBreakMode = .byTruncatingTail
        quote = ReadingSelectionTextView(frame: NSRect(x: 0, y: 0, width: 413,
                                                      height: ReadingSelectionTextView.selectionHeight))
        quote.readingFontSize = answerFontSize
        quote.setAccessibilityLabel("选中的原文"); quote.string = "选一句，读懂一点。"
        addExplanationButton = PaperButton("", kind: .quiet, symbol: "plus.circle", target: self, action: #selector(addExplanation))
        (addExplanationButton as? PaperButton)?.subduedUntilHover = true
        (addExplanationButton as? PaperButton)?.symbolPointSize = 20
        (addExplanationButton as? PaperButton)?.circularHover = true
        addExplanationButton.setAccessibilityLabel("新增解释")
        addExplanationButton.toolTip = "按当前划选位置新增一份解释，保留已有解释。"
        addExplanationButton.isHidden = true
        explanationSpinner = NSProgressIndicator()
        explanationSpinner.style = .spinning; explanationSpinner.controlSize = .small; explanationSpinner.isHidden = true
        let (chatScroll, chatView) = ReadingTextArea.make(font: PaperTheme.readingFont(answerFontSize), height: 270)
        transcript = chatView
        PaperTheme.text(transcript, font: PaperTheme.readingFont(answerFontSize), inset: NSSize(width: 0, height: 4))
        transcript.setAccessibilityLabel("AI 回答与对话")
        transcript.string = "解释与例句会出现在这里。\n\n遇到不明白的地方，可以接着问。"
        let input = PaperInputWell()
        question = ReadingQuestionView()
        let (inputScroll, _) = ReadingTextArea.make(font: .systemFont(ofSize: 13), height: 23, textView: question)
        questionScroll = inputScroll
        question.isEditable = true; question.isRichText = false; question.allowsUndo = true
        PaperTheme.text(question, font: .systemFont(ofSize: 13), inset: NSSize(width: 0, height: 2))
        question.textContainer?.lineFragmentPadding = 0
        question.placeholderAttributedString = NSAttributedString(string: "继续问一句…", attributes: [.foregroundColor: PaperTheme.muted.withAlphaComponent(0.8)])
        question.toolTip = "最多 5000 字符；Return 发送，Shift+Return 换行；长问题可滚动"
        question.focusRingType = .none
        question.onSubmit = { [weak self] in self?.sendQuestion() }
        question.onContentLayout = { [weak self] in
            self?.updateQuestionHeight()
            self?.updateQuestionLengthHint()
        }
        question.setAccessibilityLabel("继续提问")
        sendButton = PaperButton("", kind: .primary, symbol: "arrow.up", target: self, action: #selector(sendOrStop))
        sendButton.setAccessibilityLabel("发送"); sendButton.toolTip = "发送（Return）"
        for view in [inputScroll, sendButton!] { view.translatesAutoresizingMaskIntoConstraints = false; input.addSubview(view) }
        questionHeight = input.heightAnchor.constraint(equalToConstant: 43)
        status = NSTextField(labelWithString: "准备就绪")
        status.font = .systemFont(ofSize: 10); status.textColor = PaperTheme.muted
        status.lineBreakMode = .byTruncatingTail
        updateQuestionLengthHint()
        for view in [toolbar, answerSizeLabel!, contextLabel!, quote!, addExplanationButton!, explanationSpinner!, chatScroll, input, status!] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        quoteHeight = quote.heightAnchor.constraint(equalToConstant: quote.excerptHeight)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            toolbar.heightAnchor.constraint(equalToConstant: 30),
            answerSizeLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            answerSizeLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2),
            contextLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 18),
            contextLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            contextLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            quote.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 8),
            quote.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor, constant: -13),
            quote.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -47),
            addExplanationButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -17),
            addExplanationButton.topAnchor.constraint(equalTo: quote.topAnchor, constant: 8),
            addExplanationButton.widthAnchor.constraint(equalToConstant: 28),
            addExplanationButton.heightAnchor.constraint(equalToConstant: 28),
            explanationSpinner.centerXAnchor.constraint(equalTo: addExplanationButton.centerXAnchor),
            explanationSpinner.topAnchor.constraint(equalTo: addExplanationButton.bottomAnchor, constant: 2),
            quoteHeight,
            chatScroll.topAnchor.constraint(equalTo: quote.bottomAnchor, constant: 12),
            chatScroll.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor, constant: -5),
            chatScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -21),
            chatScroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -10),
            input.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            input.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            input.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            questionHeight,
            inputScroll.leadingAnchor.constraint(equalTo: input.leadingAnchor),
            inputScroll.topAnchor.constraint(equalTo: input.topAnchor, constant: 12),
            inputScroll.bottomAnchor.constraint(equalTo: input.bottomAnchor, constant: -8),
            inputScroll.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            sendButton.trailingAnchor.constraint(equalTo: input.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: input.bottomAnchor, constant: -3),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
            status.leadingAnchor.constraint(equalTo: contextLabel.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: contextLabel.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        content.onLayout = { [weak self] width in
            self?.updateToolbar(width: width)
            self?.updateQuestionHeight()
        }
        updateToolbar(width: panel.frame.width)
        updateReadingStyle()
    }
}
