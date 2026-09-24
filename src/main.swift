import AppKit
import Foundation
@preconcurrency import ApplicationServices

@MainActor
final class BookAsk: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    var panel: AskPanel!
    var hasWindowPosition = false
    var quote: ReadingSelectionTextView!
    var transcript: NSTextView!
    var question: ReadingQuestionView!
    var questionScroll: NSScrollView!
    var questionHeight: NSLayoutConstraint!
    var updatingQuestionHeight = false
    var status: NSTextField!
    var contextLabel: NSTextField!
    var sendButton: NSButton!
    var automaticButton: NSButton!
    var popupButton: NSButton!
    var smallerAnswerButton: NSButton!
    var largerAnswerButton: NSButton!
    var answerSizeLabel: NSTextField!
    var styleButton: NSButton!
    var appearanceButton: NSButton!
    var pinButton: NSButton!
    var quoteHeight: NSLayoutConstraint!
    var toolbarCompact = false
    var sizeFeedbackWork: DispatchWorkItem?
    var promptPanel: AskPanel?
    var promptDraftEditor: NSTextView?
    var promptLimitLabel: NSTextField?
    var promptGuidanceLabel: NSTextField?
    var styleMenuItems: [NSMenuItem] = []
    var answerFontSize = ReadingPreferences.answerFontSize()
    var panelController: ReadingPanelController!
    var promptEditor: NSTextView!
    var promptScroll: NSScrollView!
    var promptHeight: NSLayoutConstraint!
    var promptDisclosure: NSButton!
    var wordbook: WordbookView?
    var readingContent: NSView!
    var showingWordbook = false
    var wordbookLibrary = WordbookLibrary.shared
    var lookupTask: Task<Void, Never>?
    var wordbookReady = false
    var currentWordbookEntry: WordbookEntry?
    var activeDefinitionID: String?
    var readingPage: ReadingPageSnapshot?
    var selectionContextTask: Task<Void, Never>?
    var selectionContext = ContextMatch(paragraphs: [], status: "仅依据选中文字")
    var selectionBook = "图书"
    var answerBook = "图书"
    var preservingAnswer = false
    var addExplanationButton: NSButton!
    var explanationSpinner: NSProgressIndicator!
    var contextResolver: (String, ReadingPageSnapshot?) async -> LocalContextResult = {
        await LocalBookContext.shared.resolve(selection: $0, page: $1)
    }
    var modelSession = URLSession.shared
    // Injectable I/O boundaries let request-count tests use isolated storage and
    // a local URLProtocol without showing windows or writing personal history.
    var configurationLoader: () throws -> Configuration = Configuration.load
    var configurationFailure: String?
    var recordSink: (([String: Any]) -> Void)?
    var windowPresenter: ((String) -> Void)?
    var promptExpanded = false
    var statusItem: NSStatusItem!
    var automaticMenu: NSMenuItem!
    var popupMenu: NSMenuItem!
    var appearanceMenuItems: [NSMenuItem] = []
    var captureTimer: Timer?
    var autoExplain = ReadingPreferences.automatic
    var autoPopup = ReadingPreferences.automaticPopup
    var manualIntent = SelectionActionIntent()
    var actionContextProvider: () -> SelectionActionContext = { .current() }
    // Suppresses window presentation in state-machine tests, without replacing
    // the gesture, intent consumption or copy scheduling logic.
    var actionOfferPresenter: ((NSPoint) -> Bool)?
    lazy var selectionActionController: SelectionActionController = {
        let controller = SelectionActionController()
        controller.onConfirm = { [weak self] in self?.confirmSelectionAction() }
        controller.onCancel = { [weak self] reason in self?.invalidateManualSelection(reason: reason) }
        return controller
    }()
    var manualPlacement: ReadingPanelPlacement?
    var keyboardMonitor: Any?
    var activeCaptureIsManual = false
    // Tests observe the scheduling boundary without touching a real clipboard.
    var copyScheduleSink: ((pid_t, Int, ReadingPanelPlacement?, Bool) -> Void)?
    var activeRequestIsAutomatic = false
    var selectionTrigger = SelectionTrigger()
    var selectionReadInProgress = false
    var monitorState = ""
    var nextReadDiagnosticAt = Date.distantPast
    var nextTickDiagnosticAt = Date.distantPast
    var lastCaptureGate = ""
    var selectionInteraction = SelectionInteraction()
    var interactionRevision: Int { selectionInteraction.revision }
    var currentSampleID = ""
    var currentRequestID = ""
    var latestRead: [String: Any] = [:]
    var mouseMonitor: Any?
    var lastDragLogTime = 0.0
    var booksObserver: AXObserver?
    var observedBooksPID: pid_t = 0
    var booksActivity: NSObjectProtocol?
    var workspaceObserver: NSObjectProtocol?
    var spaceObserver: NSObjectProtocol?
    var lastBooksFullScreen: Bool?
    var recentSelectionEvent = Date.distantPast
    var selectionEventElement: AXUIElement?
    let selectionQueue = DispatchQueue(label: "com.zydtr.book-ask.selection", qos: .userInitiated)
    var selectedText = ""
    var messages: [[String: String]] = []
    var displayHistory = NSAttributedString(string: "")
    var sessionId = UUID().uuidString
    var activeTask: Task<Void, Never>?
    var activeGeneration = UUID()
    var config: Configuration?
    var context: ContextMatch = ContextMatch(paragraphs: [], status: "")
    var copyCaptureEnabled = ReadingPreferences.copyCapture
    var gestureHadDrag = false
    var captureInFlight = false
    var pendingCaptureWork: DispatchWorkItem?
    var activeCaptureID = ""
    /// Serial queue running one clipboard transaction at a time; a newer gesture's
    /// transaction waits here until the invalidated older one has cleaned up.
    let captureQueue = DispatchQueue(label: "com.zydtr.book-ask.capture")
    var lastCopyAccepted = ""
    var currentPlacement: ReadingPanelPlacement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        buildMenu()
        buildWindow()
        panelController.startMonitoring()
        selectionActionController.startMonitoring()
        record(["event": "window_policy", "activationPolicy": NSApp.activationPolicy().rawValue,
                "isUIElement": Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false,
                "level": panel.level.rawValue,
                "joinsAllSpaces": panel.collectionBehavior.contains(.canJoinAllSpaces),
                "appearance": ReadingPreferences.appearance().rawValue,
                "darkPaper": PaperTheme.isDark(panel.effectiveAppearance)])
        reloadConfiguration()
        status.stringValue = configurationFailure ?? (AXIsProcessTrusted() ? readyStatus : "首次使用：从菜单栏打开「使用指南」")
        buildStatusItem()
        DiagnosticLog.shared.record(["event": "launch", "processID": ProcessInfo.processInfo.processIdentifier,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "model": config?.model ?? "",
            "screenFrames": NSScreen.screens.map { NSStringFromRect($0.frame) },
            "logPolicy": "always_on; changed samples + 10s unchanged heartbeat; 30-sample pre-trigger trace; 6 x 10 MiB"])
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The offer owns its click, even if the monitor sees Books as
                // frontmost. Never count it as a new selection gesture.
                if self.selectionActionController.contains(NSEvent.mouseLocation),
                   event.type == .leftMouseDown || event.type == .leftMouseUp { return }
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BooksSelection.bundleID else {
                    self.invalidateManualSelection(reason: "input_outside_books")
                    return
                }
                if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .scrollWheel {
                    self.invalidateManualSelection(reason: "mouse_or_scroll")
                }
                if event.type == .scrollWheel {
                    if !self.autoPopup { self.pendingCaptureWork?.cancel(); self.activeCaptureID = "" }
                    return
                }
                let dragging = event.type == .leftMouseDragged
                let now = ProcessInfo.processInfo.systemUptime
                if event.type == .leftMouseDown { self.gestureHadDrag = false }
                if dragging { self.gestureHadDrag = true }
                if !dragging {
                    self.selectionInteraction.event(buttons: Int(NSEvent.pressedMouseButtons))
                    self.selectionTrigger.interrupt("books_mouse_event")
                }
                if !dragging || now - self.lastDragLogTime >= 0.1 {
                    DiagnosticLog.shared.record(["event": "books_mouse_event", "type": event.type.rawValue,
                        "eventTimestamp": event.timestamp, "clickCount": event.clickCount,
                        "location": NSStringFromPoint(NSEvent.mouseLocation),
                        "interactionRevision": self.interactionRevision])
                    self.lastDragLogTime = now
                }
                if event.type == .leftMouseUp {
                    // Only a real selection gesture may issue a copy; plain clicks,
                    // scrolls and startup leftovers never touch the clipboard.
                    if BooksCopy.isSelectionGesture(dragged: self.gestureHadDrag, clickCount: event.clickCount, button: 0),
                       let books = NSWorkspace.shared.frontmostApplication {
                        self.handleSelectionGesture(pid: books.processIdentifier,
                            placement: ReadingPanelPlacement.capture(mouseUp: event, booksPID: books.processIdentifier))
                    }
                    self.gestureHadDrag = false
                }
                if event.type == .leftMouseUp || event.type == .rightMouseUp { self.captureBooksSelection() }
            }
        }
        refreshKeyboardMonitor(trusted: AXIsProcessTrusted())
        captureTimer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureBooksSelection() }
        }
        RunLoop.main.add(captureTimer!, forMode: .common)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateManualSelection(reason: "application_changed")
                if self?.autoPopup == false { self?.pendingCaptureWork?.cancel(); self?.activeCaptureID = "" }
                self?.captureBooksSelection()
            }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBooksConnection() }
        }
        record(["event": "selection_monitor_started", "enabled": true, "automatic": autoExplain,
                "autoPopup": autoPopup, "dismissKeyMonitor": keyboardMonitor != nil,
                "copyCapture": copyCaptureEnabled, "accessibilityTrusted": AXIsProcessTrusted()])
        showWindow(reason: "launch")
        if selectedText.isEmpty { showWelcomeText() }
        if !UserDefaults.standard.bool(forKey: "hasSeenGettingStarted") {
            showGettingStarted()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(reason: "reopen")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stopMonitoring()
        selectionActionController.stopMonitoring()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        pendingCaptureWork?.cancel()
        DiagnosticLog.shared.record(["event": "shutdown"])
        _ = DiagnosticLog.shared.flush()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pendingCaptureWork?.cancel()
        activeCaptureID = ""
        // Keep the main loop alive for a transaction's cancellation checks and
        // clipboard cleanup. Forced process termination remains outside this path.
        captureQueue.async {
            DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func buildMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示读书提问", action: #selector(openWindow), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "词本", action: #selector(openWordbook), keyEquivalent: "b").target = self
        appMenu.addItem(withTitle: "使用指南", action: #selector(showGettingStarted), keyEquivalent: "").target = self
        appMenu.addItem(makeAppearanceMenu())
        appMenu.addItem(withTitle: "记录划词问题并打开日志", action: #selector(reportSelectionIssue), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "授权划词", action: #selector(requestAccessibility), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出读书提问", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }


    var readyStatus: String {
        let trigger = autoPopup ? "划词弹窗" : "划词后点「问 AI」"
        return trigger + (autoExplain ? " · 自动发送" : " · 手动发送提问")
    }

    func reloadConfiguration() {
        do {
            config = try configurationLoader()
            configurationFailure = nil
            if let key = try? config?.credential() { DiagnosticLog.shared.registerSecret(key) }
        } catch {
            config = Configuration()
            configurationFailure = ConfigurationError.invalidFile.localizedDescription
        }
    }

    func showWelcomeText() {
        quote.string = "留在书里，随时问一句"
        contextLabel.stringValue = "先打开 Apple Books 中的一本书"
        showConversation(NSAttributedString(string: ""), answer:
            "划选一个词或短句，点鼠标旁的「问 AI」，即可打开提问窗口。\n\n开启「划词弹窗」后，划选就会显示窗口；「自动发送」决定是否立即发送。\n\n你可以编辑提示词、继续追问，或从「词本」回看保存在本机的记录。\n\n首次使用请从菜单栏「书问 → 使用指南」完成辅助功能授权。")
    }

    @objc func showGettingStarted() {
        showWindow(reason: "getting_started")
        guard panel.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "在图书里，随时问一句"
        alert.informativeText = "1. 开启「读书提问」的辅助功能权限。\n2. 在 Apple Books 划选文字，点鼠标旁的「问 AI」。\n3. 在浮窗阅读解释或继续提问。\n\n也可以勾选「划词弹窗」，划词后直接显示窗口。\n\n读取选区会临时复制并恢复剪贴板；提问时会把选区、问题与本轮对话发送到模型服务。历史只保存在本机。"
        let trusted = AXIsProcessTrusted()
        alert.addButton(withTitle: trusted ? "开始阅读" : "打开辅助功能设置")
        alert.addButton(withTitle: "稍后")
        alert.beginSheetModal(for: panel) { [weak self] response in
            UserDefaults.standard.set(true, forKey: "hasSeenGettingStarted")
            if response == .alertFirstButtonReturn, !trusted { self?.requestAccessibility() }
        }
    }

    func refreshKeyboardMonitor(trusted: Bool) {
        if !trusted {
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
            keyboardMonitor = nil
            invalidateManualSelection(reason: "permission_missing")
            return
        }
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleDismissKey(event) }
        }
        record(["event": "keyboard_monitor_refreshed", "trusted": trusted, "installed": keyboardMonitor != nil])
    }

    func makeAppearanceMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "外观")
        for style in ReadingStyle.allCases {
            let option = menu.addItem(withTitle: style.title, action: #selector(selectReadingStyle(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = style.rawValue
            option.state = ReadingPreferences.style() == style ? .on : .off
            styleMenuItems.append(option)
        }
        menu.addItem(.separator())
        for choice in ReadingAppearance.allCases {
            let option = menu.addItem(withTitle: choice.title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = choice.rawValue
            option.state = ReadingPreferences.appearance() == choice ? .on : .off
            appearanceMenuItems.append(option)
        }
        item.submenu = menu
        return item
    }

    @objc func toggleReadingStyle() {
        setReadingStyle(ReadingPreferences.style() == .books ? .paper : .books)
    }

    @objc func selectReadingStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = ReadingStyle(rawValue: raw) else { return }
        setReadingStyle(style)
    }

    func setReadingStyle(_ style: ReadingStyle) {
        ReadingPreferences.setStyle(style)
        for item in styleMenuItems { item.state = item.representedObject as? String == style.rawValue ? .on : .off }
        updateReadingStyle()
        wordbook?.refreshStyle()
        PaperTheme.apply(ReadingPreferences.appearance(), to: panel)
        panel.invalidateShadow()
        record(["event": "reading_style_changed", "style": style.rawValue])
    }

    func updateReadingStyle() {
        styleButton.title = ReadingPreferences.style() == .paper ? "纸感" : "图书"
        styleButton.setAccessibilityLabel("切换阅读外观：" + ReadingPreferences.style().title)
        styleButton.toolTip = "当前为" + ReadingPreferences.style().title + "，点击切换阅读风格"
        updateExcerptSize()
        contextLabel.textColor = PaperTheme.muted; status.textColor = PaperTheme.muted
        updateQuestionLengthHint()
        answerSizeLabel.textColor = PaperTheme.muted; question.textColor = PaperTheme.ink
        question.insertionPointColor = PaperTheme.coral
        question.placeholderAttributedString = NSAttributedString(string: "继续问一句…", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: PaperTheme.muted.withAlphaComponent(0.8)])
        promptScroll.backgroundColor = PaperTheme.blue.withAlphaComponent(0.1)
        PaperTheme.text(promptEditor, font: .systemFont(ofSize: 12))
        transcript.selectedTextAttributes = [.backgroundColor: PaperTheme.blue.withAlphaComponent(0.35), .foregroundColor: PaperTheme.ink]
        displayHistory = resizedConversation(displayHistory)
        transcript.textStorage?.setAttributedString(resizedConversation(transcript.attributedString()))
        transcript.typingAttributes = [.font: PaperTheme.readingFont(answerFontSize), .foregroundColor: PaperTheme.ink, .paragraphStyle: PaperTheme.readingParagraph(answerFontSize)]
    }

    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ReadingAppearance(rawValue: raw) else { return }
        ReadingPreferences.setAppearance(choice)
        for item in appearanceMenuItems {
            item.state = item.representedObject as? String == raw ? .on : .off
        }
        PaperTheme.apply(choice, to: panel)
        record(["event": "appearance_changed", "appearance": raw,
                "darkPaper": PaperTheme.isDark(panel.effectiveAppearance)])
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = autoExplain ? "书问 ●" : "书问"
        statusItem.button?.toolTip = "读书提问：在 Mac 图书中划选即可提问"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示读书提问", action: #selector(openWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "词本", action: #selector(openWordbook), keyEquivalent: "").target = self
        menu.addItem(withTitle: "使用指南", action: #selector(showGettingStarted), keyEquivalent: "").target = self
        menu.addItem(makeAppearanceMenu())
        menu.addItem(withTitle: "记录划词问题并打开日志", action: #selector(reportSelectionIssue), keyEquivalent: "").target = self
        popupMenu = NSMenuItem(title: "划词弹窗", action: #selector(toggleAutomaticPopup), keyEquivalent: "")
        popupMenu.target = self; popupMenu.state = autoPopup ? .on : .off
        menu.addItem(popupMenu)
        automaticMenu = NSMenuItem(title: "自动发送", action: #selector(toggleAutomatic), keyEquivalent: "")
        automaticMenu.target = self
        automaticMenu.state = autoExplain ? .on : .off
        menu.addItem(automaticMenu)
        menu.addItem(withTitle: "授权划词", action: #selector(requestAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc func toggleAutomatic() {
        autoExplain.toggle()
        ReadingPreferences.automatic = autoExplain
        automaticButton.state = autoExplain ? .on : .off
        automaticMenu?.state = autoExplain ? .on : .off
        statusItem?.button?.title = autoExplain ? "书问 ●" : "书问"
        if !autoExplain, activeRequestIsAutomatic { stop() }
        status.stringValue = readyStatus
        record(["event": "automatic_changed", "automatic": autoExplain])
    }

    @objc func toggleAutomaticPopup() {
        autoPopup.toggle()
        ReadingPreferences.automaticPopup = autoPopup
        popupButton.state = autoPopup ? .on : .off
        popupMenu?.state = autoPopup ? .on : .off
        pendingCaptureWork?.cancel(); activeCaptureID = ""
        invalidateManualSelection(reason: "popup_mode_changed")
        selectionTrigger.interrupt("popup_mode_changed")
        status.stringValue = readyStatus
        record(["event": "automatic_popup_changed", "autoPopup": autoPopup])
    }

    func updateQuestionHeight() {
        guard !updatingQuestionHeight, let question, let questionHeight,
              let layout = question.layoutManager, let container = question.textContainer else { return }
        updatingQuestionHeight = true
        defer { updatingQuestionHeight = false }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height + question.textContainerInset.height * 2
        let cap = max(43, min(90, (readingContent?.bounds.height ?? 539) - (quoteHeight?.constant ?? 72) - 183))
        questionHeight.constant = min(cap, max(43, ceil(used) + 20))
        question.needsDisplay = true
    }

    func invalidateManualSelection(reason: String) {
        if let token = manualIntent.token {
            record(["event": "selection_action_dismissed", "reason": reason,
                    "booksPID": token.pid, "interactionRevision": token.revision])
        }
        manualIntent.reset(); manualPlacement = nil
        selectionActionController.hide()
        if !autoPopup {
            pendingCaptureWork?.cancel()
            activeCaptureID = ""
        }
    }

    func handleSelectionGesture(pid: pid_t, placement: ReadingPanelPlacement?) {
        if autoPopup {
            if copyCaptureEnabled { scheduleCopyCapture(pid: pid, gestureRevision: interactionRevision, placement: placement, manual: false) }
            return
        }
        invalidateManualSelection(reason: "new_selection")
        let context = actionContextProvider()
        guard context.trusted, context.booksPID == pid, context.mouseButtons == 0, let placement else {
            record(["event": "selection_action_rejected", "reason": "offer_context_invalid", "trusted": context.trusted])
            return
        }
        manualIntent.arm(pid: pid, revision: interactionRevision)
        manualPlacement = placement
        let shown = actionOfferPresenter?(placement.mousePoint) ?? selectionActionController.show(near: placement.mousePoint)
        guard shown else { invalidateManualSelection(reason: "display_unavailable"); return }
        record(["event": "selection_action_shown", "booksPID": pid, "interactionRevision": interactionRevision,
                "placement": placement.diagnostics, "buttonFrame": NSStringFromRect(selectionActionController.panel.frame)])
    }

    func confirmSelectionAction() {
        let context = actionContextProvider()
        guard !autoPopup, context.trusted else {
            invalidateManualSelection(reason: "click_mode_or_permission_changed")
            return
        }
        let placement = manualPlacement
        let token = manualIntent.consume(pid: context.booksPID, revision: interactionRevision, mouseDown: context.mouseButtons != 0)
        manualPlacement = nil
        selectionActionController.hide()
        guard let token else {
            record(["event": "selection_action_rejected", "reason": "click_context_invalid"])
            return
        }
        record(["event": "selection_action_clicked", "booksPID": token.pid, "interactionRevision": token.revision])
        scheduleCopyCapture(pid: token.pid, gestureRevision: token.revision, placement: placement, manual: true)
    }

    func handleDismissKey(_ event: NSEvent) {
        guard !BooksCopy.isOwnCopyEvent(event) else { return }
        invalidateManualSelection(reason: "keyboard_input")
    }

    /// A press on our nonactivating offer is not a change in the Books selection.
    /// All other mouse transitions continue to invalidate stale manual intents.
    @discardableResult func observeSelectionMouse(buttons: Int, point: NSPoint) -> Bool {
        if manualIntent.token != nil, selectionActionController.contains(point) { return false }
        let changed = selectionInteraction.observe(buttons: buttons)
        if changed { invalidateManualSelection(reason: "mouse_state_changed") }
        return changed
    }

    @objc func decreaseAnswerSize() { changeAnswerSize(to: answerFontSize - 1) }
    @objc func increaseAnswerSize() { changeAnswerSize(to: answerFontSize + 1) }
    @objc func dismissReadingPanel() { panelController.dismiss(reason: "close_button") }

    func changeAnswerSize(to size: Double) {
        answerFontSize = ReadingPreferences.boundedAnswerFontSize(size)
        ReadingPreferences.setAnswerFontSize(answerFontSize)
        updateAnswerSizeControls()
        updateExcerptSize()
        showSizeFeedback()
        let scroll = transcript.enclosingScrollView!
        // Keep the first visible character anchored as wrapping changes.
        let point = scroll.contentView.bounds.origin
        let manager = transcript.layoutManager!, container = transcript.textContainer!
        manager.ensureLayout(for: container)
        let glyph = manager.glyphIndex(for: NSPoint(x: 0, y: max(0, point.y - transcript.textContainerInset.height)), in: container)
        let character = glyph < manager.numberOfGlyphs ? manager.characterIndexForGlyph(at: glyph) : 0
        displayHistory = resizedConversation(displayHistory)
        transcript.textStorage?.setAttributedString(resizedConversation(transcript.attributedString()))
        transcript.typingAttributes[.font] = PaperTheme.readingFont(answerFontSize)
        manager.ensureLayout(for: container)
        if point.y > 0, character < transcript.string.utf16.count {
            let newGlyph = manager.glyphIndexForCharacter(at: character)
            let rect = manager.lineFragmentRect(forGlyphAt: newGlyph, effectiveRange: nil)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: rect.minY + transcript.textContainerInset.height))
        } else { scroll.contentView.scroll(to: .zero) }
        scroll.reflectScrolledClipView(scroll.contentView)
        record(["event": "answer_font_size_changed", "points": answerFontSize])
    }

    func updateAnswerSizeControls() {
        smallerAnswerButton.toolTip = "缩小原文与回答 · 当前 \(Int(answerFontSize))"
        largerAnswerButton.toolTip = "放大原文与回答 · 当前 \(Int(answerFontSize))"
        smallerAnswerButton.isEnabled = answerFontSize > ReadingPreferences.answerFontRange.lowerBound
        largerAnswerButton.isEnabled = answerFontSize < ReadingPreferences.answerFontRange.upperBound
    }

    // Resize by font descriptor, preserving role weight and all colors. SSE
    // prefixes may have been captured before a size change, so rebase every draw.
    func resizedConversation(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        // Recreate through the system interface at each point size so New York
        // receives the appropriate optical design, not a scaled old descriptor.
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            result.addAttributes([.font: PaperTheme.readingFont(answerFontSize),
                .foregroundColor: attributes[PaperTheme.questionRole] as? Bool == true ? PaperTheme.coral : PaperTheme.ink,
                .paragraphStyle: PaperTheme.readingParagraph(answerFontSize)], range: range)
        }
        PaperTheme.compactParagraphBreaks(result)
        return NSAttributedString(attributedString: result)
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView else { return }
        if editor === promptDraftEditor { updatePromptLengthHint(); return }
        guard editor === promptEditor else { return }
        guard InputLengthLimit.allows(editor.string) else {
            status.stringValue = InputLengthLimit.rejection("提示词", action: "保存")
            return
        }
        ReadingPreferences.prompt = editor.string
        if activeTask == nil {
            status.stringValue = editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "提示词为空 · 填写后才能自动解释" : "提示词已保存 · 下次划选时生效"
        }
    }

    @objc func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        refreshKeyboardMonitor(trusted: trusted)
        status.stringValue = trusted ? readyStatus : "请在系统设置 → 隐私与安全性 → 辅助功能中开启「读书提问」"
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func captureBooksSelection() {
        let trusted = AXIsProcessTrusted()
        refreshKeyboardMonitor(trusted: trusted)
        let booksFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BooksSelection.bundleID
        if booksFrontmost, trusted, booksActivity == nil {
            booksActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Respond to the user's selection in Apple Books")
        } else if !booksFrontmost || !trusted, let activity = booksActivity {
            ProcessInfo.processInfo.endActivity(activity)
            booksActivity = nil
        }
        let books = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first
        if trusted, let books, books.processIdentifier != observedBooksPID {
            attachBooksObserver(pid: books.processIdentifier)
        }
        let now = ProcessInfo.processInfo.systemUptime
        let mouseButtons = Int(NSEvent.pressedMouseButtons)
        if observeSelectionMouse(buttons: mouseButtons, point: NSEvent.mouseLocation) {
            selectionTrigger.interrupt(mouseButtons == 0 ? "mouse_released" : "mouse_down")
            DiagnosticLog.shared.record(["event": "mouse_state", "buttons": mouseButtons,
                "interactionRevision": interactionRevision, "booksInForeground": booksFrontmost])
        }
        let gate = !trusted ? "permission_missing" : (books == nil ? "books_not_running" :
            (mouseButtons != 0 ? "mouse_down" : (selectionReadInProgress ? "read_in_progress" : "reading")))
        if gate != lastCaptureGate && gate != "read_in_progress" || Date() >= nextTickDiagnosticAt {
            DiagnosticLog.shared.record(["event": "capture_gate", "gate": gate, "trusted": trusted,
                "booksInForeground": booksFrontmost, "mouseButtons": mouseButtons,
                "readInProgress": selectionReadInProgress, "automatic": autoExplain])
            nextTickDiagnosticAt = Date().addingTimeInterval(10)
        }
        lastCaptureGate = gate
        let state = "\(autoPopup):\(autoExplain):\(trusted):\(booksFrontmost)"
        if state != monitorState {
            monitorState = state
            record(["event": "selection_monitor_state", "enabled": true, "automatic": autoExplain, "autoPopup": autoPopup, "accessibilityTrusted": trusted, "booksInForeground": booksFrontmost])
            if selectedText.isEmpty, trusted { status.stringValue = readyStatus }
        }
        guard autoPopup, !selectionReadInProgress, AXIsProcessTrusted(),
              NSEvent.pressedMouseButtons == 0,
              let front = books else { return }
        selectionReadInProgress = true
        let sampleID = UUID().uuidString
        let inspectDetails = Date() >= nextReadDiagnosticAt
        if inspectDetails { nextReadDiagnosticAt = Date().addingTimeInterval(10) }
        let interactionAtStart = interactionRevision
        let pid = front.processIdentifier
        let preferred = Date().timeIntervalSince(recentSelectionEvent) < 2 ? selectionEventElement : nil
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
        selectionQueue.async { [weak self] in
            let result = BooksSelection.inspect(pid: pid, preferred: preferred, point: point, diagnostics: inspectDetails)
            let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.selectionReadInProgress = false
                var sample = result.diagnostics
                sample["event"] = "selection_sample"
                sample["sampleID"] = sampleID
                sample["treeSnapshot"] = inspectDetails
                sample["startedUptime"] = now
                sample["rawText"] = result.text ?? ""
                sample["normalizedText"] = text
                sample["mousePoint"] = NSStringFromPoint(point)
                sample["mouseButtonsAtCompletion"] = NSEvent.pressedMouseButtons
                sample["booksInForegroundAtStart"] = booksFrontmost
                sample["booksInForegroundAtCompletion"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                sample["interactionRevision"] = interactionAtStart
                if let fullScreen = result.diagnostics["focusedWindowFullScreen"] as? Bool,
                   result.diagnostics["windowTitle"] as? String != "missing",
                   fullScreen != self.lastBooksFullScreen {
                    self.lastBooksFullScreen = fullScreen
                    self.refreshBooksConnection()
                    self.record(["event": "books_window_mode", "fullScreen": fullScreen])
                }
                let selected: String?
                if interactionAtStart != self.interactionRevision {
                    self.selectionTrigger.interrupt("interaction_changed_during_read")
                    selected = nil
                } else {
                    selected = self.selectionTrigger.sample(text, source: pid,
                        frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                        mouseDown: NSEvent.pressedMouseButtons != 0,
                        complete: result.diagnostics["reason"] as? String == "no_selection",
                        now: ProcessInfo.processInfo.systemUptime)
                }
                sample["trigger"] = self.selectionTrigger.evidence
                self.latestRead = sample
                let selectedSource = result.diagnostics["selectedSource"] as? [String: Any] ?? [:]
                let signatureFields: [String: Any] = ["pid": pid, "decision": self.selectionTrigger.decision,
                    "text": text, "reason": result.diagnostics["reason"] ?? "",
                    "path": selectedSource["path"] ?? "", "range": selectedSource["AXSelectedTextRange"] ?? "",
                    "fullScreen": result.diagnostics["focusedWindowFullScreen"] ?? false]
                let signature = String(decoding: (try? JSONSerialization.data(withJSONObject: signatureFields, options: .sortedKeys)) ?? Data(), as: UTF8.self)
                DiagnosticLog.shared.sample(sample, signature: signature, now: ProcessInfo.processInfo.systemUptime)
                guard self.autoPopup, let selected else { return }
                if self.copyCaptureEnabled {
                    // While the copy strategy is enabled the AX read stays purely
                    // diagnostic: a non-empty but wrong AX word must never bypass
                    // copy confirmation and reach the UI or the model.
                    DiagnosticLog.shared.record(["event": "ax_selection_suppressed", "sampleID": sampleID,
                        "characterCount": selected.count, "strategy": "books_copy"])
                    return
                }
                DiagnosticLog.shared.checkpoint(["event": "selection_accepted", "checkpointID": sampleID,
                    "sampleID": sampleID, "selection": selected, "previousSessionID": self.sessionId])
                self.record(["event": "books_selection_trigger", "sourceApp": BooksSelection.bundleID,
                    "sampleID": sampleID, "characterCount": selected.count, "booksInForeground": booksFrontmost])
                self.receive(selected, sampleID: sampleID)
            }
        }
    }

    /// Entry point from the global mouse monitor after a real selection gesture
    /// (drag or double/triple click) in a frontmost Books. Schedules one guarded
    /// copy transaction; the window is fronted only after an accepted capture.
    func scheduleCopyCapture(pid: pid_t, gestureRevision: Int, placement: ReadingPanelPlacement?, manual: Bool) {
        guard manual ? !autoPopup : (autoPopup && copyCaptureEnabled) else { return }
        if let copyScheduleSink { copyScheduleSink(pid, gestureRevision, placement, manual); return }
        guard AXIsProcessTrusted() else {
            status.stringValue = "请从菜单栏授权划词"
            record(["event": "copy_capture_blocked", "reason": "permission_missing", "manual": manual])
            return
        }
        let captureID = UUID().uuidString
        pendingCaptureWork?.cancel()
        // Assigning the active ID invalidates any older transaction; its wait loop
        // observes the mismatch and runs its own cleanup before ours starts.
        activeCaptureID = captureID
        activeCaptureIsManual = manual
        DiagnosticLog.shared.record(["event": "copy_capture_scheduled", "captureID": captureID,
            "trigger": manual ? "selection_button" : "automatic_selection",
            "booksPID": pid, "interactionRevision": gestureRevision, "settleDelay": CopyCapture.settleDelay,
            "placement": placement?.diagnostics ?? ["reason": "mouse_geometry_unavailable"]])
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.beginCopyCapture(captureID: captureID, pid: pid, gestureRevision: gestureRevision, placement: placement)
            }
        }
        pendingCaptureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CopyCapture.settleDelay, execute: work)
    }

    /// Side-effect gate: a copy is issued only if Books is still the frontmost app
    /// with the same PID, the mouse is released, the gesture is unbroken and the
    /// transaction was not superseded during the settle delay.
    func beginCopyCapture(captureID: String, pid: pid_t, gestureRevision: Int, placement: ReadingPanelPlacement?) {
        guard activeCaptureID == captureID else { return }
        let books = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let valid = (activeCaptureIsManual || copyCaptureEnabled) && AXIsProcessTrusted() && books?.processIdentifier == pid
            && front && NSEvent.pressedMouseButtons == 0 && interactionRevision == gestureRevision
        guard valid else {
            DiagnosticLog.shared.record(["event": "copy_capture_aborted", "captureID": captureID,
                "copyEnabled": copyCaptureEnabled, "trusted": AXIsProcessTrusted(),
                "booksPIDMatch": books?.processIdentifier == pid, "booksFrontmost": front,
                "mouseButtons": NSEvent.pressedMouseButtons,
                "gestureRevision": gestureRevision, "currentRevision": interactionRevision])
            if activeCaptureID == captureID { activeCaptureID = "" }
            return
        }
        captureInFlight = true
        let quartzPoint = placement.flatMap { placement in
            NSScreen.screens.first.map { CGPoint(x: placement.mousePoint.x, y: $0.frame.maxY - placement.mousePoint.y) }
        }
        captureQueue.async { [weak self] in
            let outcome = CopyCapture.run(
                pasteboard: SystemPasteboard(),
                captureID: captureID,
                issue: { outcome in
                    // Re-verify immediately before the side effect: the shortcut and
                    // the menu press are both targeted at the Books PID, but a stale
                    // gesture must not copy at all.
                    let stillValid = DispatchQueue.main.sync { () -> Bool in
                        MainActor.assumeIsolated {
                            guard let self, self.activeCaptureID == captureID else { return false }
                            return self.interactionRevision == gestureRevision
                                && NSEvent.pressedMouseButtons == 0
                                && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                        }
                    }
                    guard stillValid else { return false }
                    return BooksCopy.issue(to: pid, outcome: &outcome)
                },
                isCancelled: {
                    DispatchQueue.main.sync { () -> Bool in
                        MainActor.assumeIsolated {
                            guard let self else { return true }
                            let booksAlive = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first?.processIdentifier == pid
                            return self.activeCaptureID != captureID || self.interactionRevision != gestureRevision || !booksAlive
                                || NSWorkspace.shared.frontmostApplication?.processIdentifier != pid
                        }
                    }
                })
            let page = outcome.acceptedText.flatMap { BooksSelection.readingPage(pid: pid, selection: $0, point: quartzPoint) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishCopyCapture(outcome, pid: pid, placement: placement, page: page) }
            }
        }
    }

    func finishCopyCapture(_ outcome: CaptureOutcome, pid: pid_t, placement: ReadingPanelPlacement?, page: ReadingPageSnapshot? = nil) {
        captureInFlight = false
        let current = activeCaptureID == outcome.captureID
        if current { activeCaptureID = "" }
        var fields = outcome.logFields()
        fields["event"] = "copy_capture_outcome"
        fields["booksPID"] = pid
        if let text = outcome.acceptedText {
            fields["axCopyMatch"] = (latestRead["normalizedText"] as? String ?? "") == text
        }
        DiagnosticLog.shared.record(fields)
        // A superseded transaction still cleaned up above; only its delivery stops.
        guard current else { return }
        if let text = outcome.acceptedText {
            currentPlacement = placement
            if ReadingPreferences.cacheEnabled, text == selectedText {
                // A fresh same-word gesture keeps the user's draft but updates
                // the source location used by the explicit + action.
                currentSampleID = "copy-" + outcome.captureID
                readingPage = page
                selectionContextTask?.cancel()
                let sample = currentSampleID
                selectionContextTask = Task { @MainActor in
                    let resolved = await contextResolver(text, page)
                    guard currentSampleID == sample, !Task.isCancelled else { return }
                    selectionContext = resolved.match; selectionBook = resolved.book
                    selectionContextTask = nil; updateAddExplanation()
                }
                if activeTask == nil, let entry = currentWordbookEntry,
                   entry.definitions.first?.id != activeDefinitionID { restoreWordbook(entry) }
                updateAddExplanation()
                showWindow(reason: "repeat_selection")
                return
            }
            lastCopyAccepted = text
            // sampleID carries the captureID so history rows correlate with the
            // capture diagnostics for the same selection.
            receive(text, sampleID: "copy-" + outcome.captureID, placement: placement, page: page)
        } else {
            // Failure state is shown but never fronts the window and never falls
            // back to AX text or a previous selection.
            status.stringValue = "未能获取选中文字（\(outcome.rejection?.rawValue ?? "unknown")），请重试"
        }
    }

    func refreshBooksConnection() {
        invalidateManualSelection(reason: "books_connection_refresh")
        DiagnosticLog.shared.record(["event": "books_connection_refresh", "lastFullScreen": lastBooksFullScreen as Any? ?? "unknown"])
        selectionEventElement = nil
        recentSelectionEvent = .distantPast
        if AXIsProcessTrusted(), let books = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first {
            attachBooksObserver(pid: books.processIdentifier)
        }
    }

    func attachBooksObserver(pid: pid_t) {
        invalidateManualSelection(reason: "books_observer_changed")
        // A Books restart, Space change or fullscreen transition invalidates any
        // in-flight copy transaction; its cancellation path still cleans up.
        if !activeCaptureID.isEmpty {
            DiagnosticLog.shared.record(["event": "copy_capture_invalidated",
                "captureID": activeCaptureID, "reason": "books_connection_refresh"])
            activeCaptureID = ""
        }
        if let observer = booksObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        booksObserver = nil
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let owner = Unmanaged<BookAsk>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            Task { @MainActor in
                if name == kAXSelectedTextChangedNotification {
                    owner.recentSelectionEvent = Date()
                    owner.selectionEventElement = element
                    owner.record(["event": "books_selection_changed"])
                }
                owner.captureBooksSelection()
            }
        }, &observer)
        guard result == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var registrations = [String: Int32]()
        for name in [kAXSelectedTextChangedNotification, kAXFocusedUIElementChangedNotification] {
            registrations[name] = AXObserverAddNotification(observer, app, name as CFString, context).rawValue
        }
        booksObserver = observer
        observedBooksPID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        record(["event": "books_observer_attached", "registrations": registrations])
    }

    @objc func reportSelectionIssue() {
        let id = UUID().uuidString
        DiagnosticLog.shared.checkpoint(["event": "user_report", "checkpointID": id,
            "sessionID": sessionId, "sampleID": currentSampleID, "requestID": currentRequestID,
            "displayedSelection": quote.string, "displayedAnswer": transcript.string,
            "latestRead": latestRead, "panelFrame": NSStringFromRect(panel.frame),
            "automatic": autoExplain, "accessibilityTrusted": AXIsProcessTrusted()])
        do {
            let folder = try DiagnosticLog.shared.preserveIncident(id)
            NSWorkspace.shared.open(folder)
            status.stringValue = "问题现场已保存在本机"
        } catch { status.stringValue = "保存问题记录失败：\(error.localizedDescription)" }
    }

    @objc func openWindow() { showWindow(reason: "explicit_open") }
    @objc func openWordbook() {
        if wordbook == nil {
            wordbook = WordbookView(fallbackBook: config?.bookTitle ?? "图书", library: wordbookLibrary)
            wordbook?.onReturnToReading = { [weak self] in self?.returnToReading() }
            wordbook?.onTogglePin = { [weak self] in self?.togglePinned() }
            wordbook?.onLibraryChanged = { [weak self] term in self?.refreshDeletedDefinition(term) }
        }
        wordbook?.refreshPin(panelController.isPinned)
        showingWordbook = true
        setPage(wordbook!, title: "词本")
        wordbook?.open()
        if !panel.isVisible { showWindow(reason: "wordbook") }
        else { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wordbook?.preferredResponder) }
        record(["event": "page_changed", "page": "wordbook", "panelFrame": NSStringFromRect(panel.frame)])
    }

    func returnToReading() {
        guard showingWordbook else { return }
        showingWordbook = false
        setPage(readingContent, title: "读书提问")
        panel.makeFirstResponder(question)
        record(["event": "page_changed", "page": "reading", "panelFrame": NSStringFromRect(panel.frame)])
    }

    private func setPage(_ view: NSView, title: String) {
        let frame = panel.frame
        view.frame = NSRect(origin: .zero, size: panel.contentLayoutRect.size)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.title = title
        panel.setFrame(frame, display: false)
        view.layoutSubtreeIfNeeded()
    }
    /// Fronts the panel. Per the window contract this may only happen for a genuine
    /// new selection or an explicit user open — never from streaming, polling,
    /// answer-completion or capture-failure paths, which is why `reason` is logged.
    func showWindow(reason: String) {
        let selectionPresentation = reason == "new_selection" || reason == "repeat_selection"
        if selectionPresentation { returnToReading() }
        if let windowPresenter { windowPresenter(reason); return }
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        let selectedScreen = currentPlacement?.displayID.flatMap { id in
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        }
        let screen = (selectionPresentation ? selectedScreen : nil) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        if !panelController.isPinned, let visible = screen?.visibleFrame {
            let origin: NSPoint
            if selectionPresentation || !hasWindowPosition {
                origin = currentPlacement?.origin(in: visible, panelSize: panel.frame.size)
                    ?? NSPoint(x: max(visible.minX, visible.maxX - panel.frame.width),
                               y: max(visible.minY, visible.maxY - panel.frame.height))
            } else {
                origin = ReadingPanelController.visibleOrigin(panel.frame.origin, size: panel.frame.size, in: visible)
            }
            panel.setFrameOrigin(origin)
        }
        hasWindowPosition = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(showingWordbook ? wordbook?.preferredResponder : question)
        panelController.didPresent()
        record(["event": "window_presented", "reason": reason, "visible": panel.isVisible,
                "onActiveSpace": panel.isOnActiveSpace, "keyWindow": panel.isKeyWindow,
                "level": panel.level.rawValue, "panelFrame": NSStringFromRect(panel.frame),
                "placement": currentPlacement?.diagnostics ?? ["side": "right", "reason": "no_mouse_selection"],
                "screenVisibleFrame": screen.map { NSStringFromRect($0.visibleFrame) } ?? "unknown"])
    }

    @objc func askWithText(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType")) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "请先在图书中选中文字。"
            return
        }
        let sampleID = "service-" + UUID().uuidString
        DiagnosticLog.shared.record(["event": "service_selection", "sampleID": sampleID, "rawText": text])
        receive(text, sampleID: sampleID)
    }

    func receive(_ text: String, sampleID: String, placement: ReadingPanelPlacement? = nil, page: ReadingPageSnapshot? = nil) {
        let term = WordbookStore.key(text)
        if term == selectedText, !term.isEmpty, sampleID == currentSampleID {
            currentPlacement = placement
            showWindow(reason: "repeat_selection")
            return
        }
        stop()
        wordbookReady = false
        currentWordbookEntry = nil
        activeDefinitionID = nil
        readingPage = page
        updateAddExplanation()
        currentPlacement = placement
        currentSampleID = sampleID
        selectedText = term
        guard selectedText.count <= 6000 else {
            showWindow(reason: "new_selection")
            status.stringValue = "选区较长，请选择 6000 字符以内的一小段。"
            selectedText = ""
            return
        }
        sessionId = UUID().uuidString
        currentRequestID = ""
        messages = []
        displayHistory = NSAttributedString(string: "")
        quote.string = selectedText
        quote.scrollToBeginningOfDocument(nil)
        transcript.string = ""
        question.stringValue = ""
        reloadConfiguration()
        selectionBook = page?.bookTitle ?? "图书"
        answerBook = selectionBook
        context = ContextMatch(paragraphs: [], status: "正在定位当前语境")
        selectionContext = context
        contextLabel.stringValue = "\(selectionBook) · \(context.status)"
        record(["event": "selection_received", "selection": selectedText, "bookTitle": selectionBook, "contextIDs": []])
        showWindow(reason: "new_selection")
        resolveWordbook()
    }

    func resolveWordbook() {
        guard lookupTask == nil, !selectedText.isEmpty else { return }
        let generation = UUID(); activeGeneration = generation
        let term = selectedText, page = readingPage
        status.stringValue = "正在读取词本…"
        lookupTask = Task { @MainActor in
            do {
                let resolved = await contextResolver(term, page)
                guard generation == activeGeneration, !Task.isCancelled else { return }
                selectionBook = resolved.book; answerBook = resolved.book
                selectionContext = resolved.match; context = resolved.match
                contextLabel.stringValue = "\(resolved.book) · \(resolved.status)"
                contextLabel.toolTip = contextLabel.stringValue
                record(["event": "context_resolved", "bookTitle": resolved.book, "status": resolved.status,
                        "indexReused": resolved.indexReused, "chapter": resolved.chapter, "contextText": resolved.text])
                let entry = try await wordbookLibrary.select(term, book: resolved.book, time: ISO8601DateFormatter().string(from: Date()))
                guard generation == activeGeneration, !Task.isCancelled else { return }
                currentWordbookEntry = entry
                wordbookReady = true; lookupTask = nil
                wordbook?.reload()
                updateAddExplanation()
                if ReadingPreferences.cacheEnabled, entry.hasAnswer {
                    restoreWordbook(entry)
                    record(["event": "wordbook_cache_hit", "selection": term, "sourceBook": entry.book,
                            "exchangeCount": entry.exchanges.count, "modelRequested": false])
                } else {
                    record(["event": "wordbook_cache_miss", "selection": term, "reason": "no_complete_answer"])
                    status.stringValue = "选区已就绪 · 输入问题或留空发送模板"
                    if autoExplain {
                        guard validateRequestInput(promptEditor.string, automatic: true) else { return }
                        let prompt = promptEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if prompt.isEmpty { status.stringValue = "选区已就绪 · 请先填写上方提示词" }
                        else { ask(prompt, automatic: true) }
                    }
                }
            } catch {
                guard generation == activeGeneration else { return }
                lookupTask = nil
                status.stringValue = "词本读取失败 · 点击发送重试读取"
                transcript.string = "暂时无法读取本地词本，已保留原文件。"
                record(["event": "wordbook_read_failed", "message": error.localizedDescription])
            }
        }
    }

    func restoreWordbook(_ source: WordbookEntry, definitionID: String? = nil) {
        let entry = source.displaying(definitionID)
        activeDefinitionID = entry.definitions.first?.id
        answerBook = entry.book
        if let saved = entry.definitions.first {
            context = ContextMatch(paragraphs: saved.contextText.isEmpty ? [] : [BookParagraph(id: "saved:" + saved.id, chapter: "", text: saved.contextText)], status: saved.contextStatus)
        }
        messages = entry.conversation
        let history = NSMutableAttributedString(string: "")
        for (index, exchange) in entry.exchanges.enumerated() {
            if index > 0 {
                history.append(conversationText("\n\n"))
                history.append(conversationText("你：\(exchange.question)\n\n", isQuestion: true))
            }
            history.append(conversationText(exchange.answer))
        }
        displayHistory = resizedConversation(history)
        transcript.textStorage?.setAttributedString(displayHistory)
        transcript.scrollToBeginningOfDocument(nil)
        contextLabel.stringValue = "首次解释 · \(entry.book)"
        contextLabel.toolTip = "复用最早保留的解释，沿用保存时的语境。点击＋可按当前划选位置新增解释。"
        status.stringValue = "已从词本读取 · 可继续追问"
        updateAddExplanation()
    }

    // Keep roles as attributed segments so streaming cannot recolor questions,
    // and answer text containing a speaker label is still treated as an answer.
    func conversationText(_ text: String, isQuestion: Bool = false) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            PaperTheme.questionRole: isQuestion,
            .font: PaperTheme.readingFont(answerFontSize),
            .foregroundColor: isQuestion ? PaperTheme.coral : PaperTheme.ink,
            .paragraphStyle: PaperTheme.readingParagraph(answerFontSize)
        ])
    }

    @discardableResult
    func showConversation(_ prefix: NSAttributedString, answer: String) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(conversationText(answer))
        let resized = resizedConversation(text)
        transcript.textStorage?.setAttributedString(resized)
        return resized
    }

    @objc func sendOrStop() {
        if activeTask != nil { stop() }
        else { sendQuestion() }
    }

    @objc func sendQuestion() {
        guard activeTask == nil, lookupTask == nil, !selectedText.isEmpty else { return }
        guard validateRequestInput(question.stringValue, automatic: false) else { return }
        guard wordbookReady else { resolveWordbook(); return }
        let value = question.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty, ReadingPreferences.cacheEnabled, let entry = currentWordbookEntry, entry.hasAnswer {
            restoreWordbook(entry)
            record(["event": "wordbook_cache_hit", "selection": selectedText, "reason": "empty_send", "modelRequested": false])
            return
        }
        let prompt = value.isEmpty ? promptEditor.string.trimmingCharacters(in: .whitespacesAndNewlines) : value
        guard validateRequestInput(value.isEmpty ? promptEditor.string : question.stringValue, automatic: value.isEmpty) else { return }
        guard !prompt.isEmpty else {
            status.stringValue = "请填写问题或上方提示词"
            return
        }
        question.stringValue = ""
        ask(prompt, automatic: value.isEmpty, newDefinition: value.isEmpty && !ReadingPreferences.cacheEnabled)
    }
    @objc func stop() {
        let wasActive = activeTask != nil
        activeGeneration = UUID()
        lookupTask?.cancel(); lookupTask = nil
        selectionContextTask?.cancel(); selectionContextTask = nil
        activeTask?.cancel()
        activeTask = nil
        activeRequestIsAutomatic = false
        setBusy(false)
        if wasActive {
            if preservingAnswer { transcript.textStorage?.setAttributedString(displayHistory) }
            else { showConversation(displayHistory, answer: "\n\n已停止本次回答，可以重新提问。") }
            status.stringValue = "已停止"
            record(["event": "cancelled"])
        }
    }
    func setBusy(_ busy: Bool) {
        updateAddExplanation(busy: busy)
        (sendButton as? PaperButton)?.symbol = busy ? "stop.fill" : "arrow.up"
        sendButton?.setAccessibilityLabel(busy ? "停止回答" : "发送")
    }

    func ask(_ prompt: String, automatic: Bool = false, newDefinition: Bool = false) {
        guard activeTask == nil, !selectedText.isEmpty, let config else { return }
        if automatic, !newDefinition, ReadingPreferences.cacheEnabled, let entry = currentWordbookEntry, entry.hasAnswer {
            restoreWordbook(entry)
            return
        }
        // Recheck at the actual request boundary, including untrimmed legacy templates.
        guard validateRequestInput(automatic ? promptEditor.string : prompt, automatic: automatic),
              validateRequestInput(prompt, automatic: automatic) else { return }
        let fresh = newDefinition || activeDefinitionID == nil
        let definitionID = activeDefinitionID
        let match = fresh ? selectionContext : context
        let book = fresh ? selectionBook : answerBook
        preservingAnswer = fresh && displayHistory.length > 0
        activeRequestIsAutomatic = automatic
        currentRequestID = UUID().uuidString
        record(["event": "request_started", "automatic": automatic, "question": prompt,
                "selection": selectedText, "displayedSelection": quote.string, "model": config.model,
                "contextIDs": match.paragraphs.map(\.id)])
        let generation = UUID()
        activeGeneration = generation
        let selection = selectedText
        let previous = fresh ? [] : messages
        let prefix = NSMutableAttributedString(attributedString: fresh ? NSAttributedString(string: "") : displayHistory)
        if !previous.isEmpty { prefix.append(conversationText("\n\n")) }
        if !automatic { prefix.append(conversationText("你：\(prompt)\n\n", isQuestion: true)) }
        if !preservingAnswer { showConversation(prefix, answer: "正在思考…") }
        status.stringValue = "\(config.serviceName) · 正在连接"
        setBusy(true)
        let started = Date()
        activeTask = Task { @MainActor in
            var key = ""
            var answer = ""
            do {
                let deletionRevision = try await wordbookLibrary.requestRevision(selection)
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                if configurationFailure != nil { throw ConfigurationError.invalidFile }
                let url = try config.requestURL()
                key = try config.credential()
                DiagnosticLog.shared.registerSecret(key)
                let system = ReadingPreferences.systemPrompt
                let contextText = match.paragraphs.map(\.text).joined(separator: "\n\n")
                let initial = "书名：\(book)\n选中文字：\n<selection>\n\(selection)\n</selection>\n上下文匹配状态：\(match.status)\n<book_context>\n\(contextText)\n</book_context>"
                let bodyMessages = [["role": "system", "content": system], ["role": "user", "content": initial]] + previous + [["role": "user", "content": prompt]]
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 90
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                var body: [String: Any] = ["model": config.model, "messages": bodyMessages, "stream": true, "max_tokens": 1800]
                if let level = config.thinkingLevel {
                    // 302.AI forwards Gemini thinking options through this nested
                    // field. Omit it entirely for existing provider profiles.
                    body["extra_body"] = ["google": ["thinking_config": ["thinking_level": level.rawValue]]]
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (bytes, response) = try await modelSession.bytes(for: request)
                guard generation == activeGeneration else { return }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                record(["event": "response_headers", "httpStatus": http.statusCode,
                        "elapsedSeconds": Date().timeIntervalSince(started)])
                guard http.statusCode == 200 else {
                    throw ModelServiceError.http(http.statusCode)
                }
                var receivedContent = false
                var completedStream = false
                var finishReason = ""
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard generation == activeGeneration else { return }
                    guard line.hasPrefix("data:") else { continue }
                    let dataString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if dataString == "[DONE]" { completedStream = true; break }
                    guard let data = dataString.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    if value["error"] != nil { throw ModelServiceError.stream }
                    if let choices = value["choices"] as? [[String: Any]], let reason = choices.first?["finish_reason"] as? String { finishReason = reason }
                    if let choices = value["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
                        answer += text
                        if !receivedContent {
                            record(["event": "first_content", "elapsedSeconds": Date().timeIntervalSince(started)])
                            receivedContent = true
                        }
                        if !preservingAnswer {
                            showConversation(prefix, answer: answer)
                            transcript.scrollToEndOfDocument(nil)
                        }
                        status.stringValue = "正在回答"
                    }
                }
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                guard completedStream else { throw NSError(domain: "BookAsk", code: 4, userInfo: [NSLocalizedDescriptionKey: "连接提前结束，回答未完整接收。"] ) }
                guard finishReason != "length" else { throw NSError(domain: "BookAsk", code: 5, userInfo: [NSLocalizedDescriptionKey: "回答达到长度限制，尚未完整生成，请缩小问题范围。"] ) }
                guard !answer.isEmpty else { throw NSError(domain: "BookAsk", code: 3, userInfo: [NSLocalizedDescriptionKey: "模型没有返回文本，请重试。"] ) }
                let exchange = WordbookExchange(question: prompt, answer: answer, automatic: automatic)
                let time = ISO8601DateFormatter().string(from: Date())
                let saved: WordbookEntry
                if fresh {
                    saved = try await wordbookLibrary.appendDefinition(selection, book: book,
                        contextText: match.paragraphs.map(\.text).joined(separator: "\n\n"), contextStatus: match.status, exchange: exchange, time: time, expectedRevision: deletionRevision)
                } else if let definitionID {
                    saved = try await wordbookLibrary.appendFollowup(selection, definitionID: definitionID, exchange: exchange, time: time)
                } else { throw NSError(domain: "Wordbook", code: 3) }
                guard generation == activeGeneration, !Task.isCancelled else { return }
                currentWordbookEntry = saved
                activeDefinitionID = fresh ? saved.definitions.last?.id : definitionID
                context = match; answerBook = book
                preservingAnswer = false
                contextLabel.stringValue = "\(book) · \(match.status)"
                contextLabel.toolTip = contextLabel.stringValue
                messages = previous + [["role": "user", "content": prompt], ["role": "assistant", "content": answer]]
                displayHistory = showConversation(prefix, answer: answer)
                status.stringValue = "已完成 · 可继续追问"
                record(["event": "answer", "model": config.model, "selection": selection, "question": prompt, "answer": answer,
                        "elapsedSeconds": Date().timeIntervalSince(started), "contextIDs": match.paragraphs.map(\.id), "turn": messages.count / 2])
            } catch {
                guard generation == activeGeneration else { return }
                let errorText = key.isEmpty ? error.localizedDescription : error.localizedDescription.replacingOccurrences(of: key, with: "[REDACTED]")
                if preservingAnswer { transcript.textStorage?.setAttributedString(displayHistory) }
                else { showConversation(prefix, answer: (answer.isEmpty ? "" : answer + "\n\n") + "请求未完成：\(errorText)") }
                if !automatic, question.stringValue.isEmpty { question.stringValue = prompt }
                status.stringValue = preservingAnswer ? "新增失败 · 原解释已保留" : "请求未完成"
                status.toolTip = errorText
                record(["event": "error", "message": errorText])
            }
            if generation == activeGeneration {
                activeTask = nil
                activeRequestIsAutomatic = false
                preservingAnswer = false
                setBusy(false)
                if panel.isVisible && panel.isKeyWindow && !showingWordbook { panel.makeFirstResponder(question) }
            }
        }
    }

    func updateAddExplanation(busy: Bool? = nil) {
        let isBusy = (busy ?? (activeTask != nil || lookupTask != nil)) || selectionContextTask != nil
        addExplanationButton?.isHidden = currentWordbookEntry?.hasAnswer != true
        addExplanationButton?.isEnabled = !isBusy
        explanationSpinner?.isHidden = !isBusy || currentWordbookEntry?.hasAnswer != true
        if isBusy { explanationSpinner?.startAnimation(nil) } else { explanationSpinner?.stopAnimation(nil) }
    }

    @objc func addExplanation() {
        guard activeTask == nil, lookupTask == nil, selectionContextTask == nil, currentWordbookEntry?.hasAnswer == true,
              validateRequestInput(promptEditor.string, automatic: true) else { return }
        let prompt = promptEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { status.stringValue = "请先填写提示词"; return }
        ask(prompt, automatic: true, newDefinition: true)
    }

    func refreshDeletedDefinition(_ term: String) {
        guard selectedText == term else { return }
        Task { @MainActor in
            let entry = try? await wordbookLibrary.lookup(term, fallbackBook: selectionBook)
            guard selectedText == term else { return }
            currentWordbookEntry = entry
            let activeWasDeleted = activeDefinitionID.map { id in entry?.definitions.contains(where: { $0.id == id }) != true } ?? false
            if entry == nil || activeWasDeleted {
                stop(); activeDefinitionID = nil; messages = []; displayHistory = NSAttributedString(string: "")
                transcript.string = "这份解释已删除。"
                if let entry, ReadingPreferences.cacheEnabled, entry.hasAnswer { restoreWordbook(entry) }
                else { context = selectionContext; answerBook = selectionBook }
            }
            updateAddExplanation()
        }
    }

    func record(_ fields: [String: Any]) {
        var value = fields
        value["sessionID"] = sessionId
        value["sampleID"] = value["sampleID"] ?? currentSampleID
        value["requestID"] = currentRequestID
        value["runID"] = DiagnosticLog.shared.runID
        if let recordSink { recordSink(value); return }
        DiagnosticLog.shared.record(value)
        value["time"] = ISO8601DateFormatter().string(from: Date())
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BookAsk")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let path = root.appendingPathComponent("history.jsonl")
            if !FileManager.default.fileExists(atPath: path.path) {
                FileManager.default.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
            bytes.append(0x0a)
            try handle.write(contentsOf: bytes)
            if let event = fields["event"] as? String,
               ["selection_received", "answer", "error", "cancelled"].contains(event),
               showingWordbook { wordbook?.reload() }
        } catch {
            DiagnosticLog.shared.record(["event": "history_write_failed", "message": error.localizedDescription])
            status?.stringValue = "本地记录写入失败，请从菜单记录问题"
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { BookAsk() }
application.delegate = delegate
application.run()
