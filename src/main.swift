import AppKit
import Foundation
@preconcurrency import ApplicationServices

struct Configuration: Decodable {
    let baseURL: String
    let authFile: String
    let authProvider: String
    let model: String
    let contextFile: String
    let bookTitle: String

    static func load() throws -> Configuration {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/book-ask/config.json")
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: path))
    }

    func credential() throws -> String {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: authFile))) as? [String: [String: Any]]
        guard let key = value?[authProvider]?["key"] as? String, !key.isEmpty else {
            throw NSError(domain: "BookAsk", code: 1, userInfo: [NSLocalizedDescriptionKey: "已有 LiteLLM 凭据不可用。"])
        }
        return key
    }
}

@MainActor
final class BookAsk: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    var panel: AskPanel!
    var quote: NSTextView!
    var transcript: NSTextView!
    var question: NSTextField!
    var status: NSTextField!
    var contextLabel: NSTextField!
    var sendButton: NSButton!
    var automaticButton: NSButton!
    var autoDismissButton: NSButton!
    var panelController: ReadingPanelController!
    var promptEditor: NSTextView!
    var promptScroll: NSScrollView!
    var promptHeight: NSLayoutConstraint!
    var promptDisclosure: NSButton!
    var wordbook: WordbookWindow?
    var promptExpanded = false
    var statusItem: NSStatusItem!
    var automaticMenu: NSMenuItem!
    var captureTimer: Timer?
    var autoExplain = ReadingPreferences.automatic
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
    var displayHistory = ""
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
        record(["event": "window_policy", "level": panel.level.rawValue,
                "joinsAllSpaces": panel.collectionBehavior.contains(.canJoinAllSpaces)])
        do {
            config = try Configuration.load()
            if let key = try? config?.credential() { DiagnosticLog.shared.registerSecret(key) }
            status.stringValue = AXIsProcessTrusted() ? readyStatus : "首次使用：从菜单栏打开「授权划词」"
        } catch {
            status.stringValue = "请先运行本项目的配置脚本。"
        }
        buildStatusItem()
        DiagnosticLog.shared.record(["event": "launch", "processID": ProcessInfo.processInfo.processIdentifier,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "model": config?.model ?? "",
            "screenFrames": NSScreen.screens.map { NSStringFromRect($0.frame) },
            "logPolicy": "always_on; changed samples + 10s unchanged heartbeat; 30-sample pre-trigger trace; 6 x 10 MiB"])
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == BooksSelection.bundleID else { return }
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
                    if self.copyCaptureEnabled,
                       BooksCopy.isSelectionGesture(dragged: self.gestureHadDrag, clickCount: event.clickCount, button: 0) {
                        self.scheduleCopyCapture(mouseUp: event)
                    }
                    self.gestureHadDrag = false
                }
                if event.type == .leftMouseUp || event.type == .rightMouseUp { self.captureBooksSelection() }
            }
        }
        captureTimer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureBooksSelection() }
        }
        RunLoop.main.add(captureTimer!, forMode: .common)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureBooksSelection() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBooksConnection() }
        }
        record(["event": "selection_monitor_started", "enabled": true, "automatic": autoExplain,
                "copyCapture": copyCaptureEnabled, "accessibilityTrusted": AXIsProcessTrusted()])
        showWindow(reason: "launch")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(reason: "reopen")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stopMonitoring()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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
        autoExplain ? "划选后自动解释 · 可继续追问" : "划选后仅显示原文 · 回车或发送可提问"
    }

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
        // Restore the display choice, then keep the user's default outer size.
        // showWindow uses the selection's frozen mouse-up side, or top-right
        // when there is no mouse selection (launch and service entry).
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: 500, height: 539)), display: false)
        let content = NSView()
        panel.contentView = content
        panelController = ReadingPanelController(panel: panel, automaticDismissal: ReadingPreferences.autoDismiss,
            record: { [weak self] fields in self?.record(fields) })

        automaticButton = NSButton(checkboxWithTitle: "自动解释", target: self, action: #selector(toggleAutomatic))
        automaticButton.state = autoExplain ? .on : .off
        autoDismissButton = NSButton(checkboxWithTitle: "15 秒后自动收起", target: self, action: #selector(toggleAutoDismiss))
        autoDismissButton.font = .systemFont(ofSize: 11)
        autoDismissButton.state = ReadingPreferences.autoDismiss ? .on : .off
        autoDismissButton.toolTip = "查词弹出 15 秒后收起；在窗口内点击、输入或滚动会取消本次计时"
        promptDisclosure = NSButton(title: "编辑提示词", target: self, action: #selector(togglePromptEditor))
        promptDisclosure.bezelStyle = .inline
        promptDisclosure.font = .systemFont(ofSize: 11)
        promptDisclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        promptDisclosure.imagePosition = .imageTrailing
        promptDisclosure.toolTip = "编辑后自动保存"
        let wordbookButton = NSButton(title: "词本", target: self, action: #selector(openWordbook))
        wordbookButton.bezelStyle = .inline
        wordbookButton.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        wordbookButton.imagePosition = .imageLeading
        wordbookButton.toolTip = "查看已保存的词句与解释"
        let (editorScroll, editor) = ReadingTextArea.make(font: .systemFont(ofSize: 12), height: 100)
        promptScroll = editorScroll
        promptEditor = editor
        editor.isEditable = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = ReadingPreferences.prompt
        editor.setAccessibilityLabel("自动解释提示词")
        editor.delegate = self
        promptScroll.wantsLayer = true
        promptScroll.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        promptScroll.layer?.cornerRadius = 6
        promptScroll.isHidden = true
        promptHeight = promptScroll.heightAnchor.constraint(equalToConstant: 0)

        contextLabel = NSTextField(labelWithString: "在图书中划选，无需复制")
        contextLabel.font = .systemFont(ofSize: 11)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        let (quoteScroll, quoteView) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 63)
        quote = quoteView
        quote.setAccessibilityLabel("选中的原文")
        quote.string = "在 Mac 图书中选中词语或句子，即可在这里理解和追问。"
        let line = NSBox()
        line.boxType = .separator
        let (chatScroll, chatView) = ReadingTextArea.make(font: .systemFont(ofSize: 15), height: 210)
        transcript = chatView
        transcript.setAccessibilityLabel("AI 回答与对话")
        question = NSTextField()
        question.placeholderString = "继续提问… 留空可发送上方提示词"
        question.font = .systemFont(ofSize: 14)
        question.delegate = self
        question.target = self
        question.action = #selector(sendQuestion)
        question.setAccessibilityLabel("继续提问")
        sendButton = NSButton(title: "发送", target: self, action: #selector(sendOrStop))
        let input = NSStackView(views: [question, sendButton])
        input.orientation = .horizontal
        input.spacing = 8
        question.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status = NSTextField(labelWithString: "准备就绪")
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        for view in [automaticButton!, autoDismissButton!, wordbookButton, promptDisclosure!, promptScroll!, contextLabel!, quoteScroll, line, chatScroll, input, status!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            automaticButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            automaticButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            autoDismissButton.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            autoDismissButton.leadingAnchor.constraint(equalTo: automaticButton.trailingAnchor, constant: 12),
            promptDisclosure.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            promptDisclosure.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            wordbookButton.centerYAnchor.constraint(equalTo: automaticButton.centerYAnchor),
            wordbookButton.trailingAnchor.constraint(equalTo: promptDisclosure.leadingAnchor, constant: -16),
            wordbookButton.leadingAnchor.constraint(greaterThanOrEqualTo: autoDismissButton.trailingAnchor, constant: 12),
            promptScroll.topAnchor.constraint(equalTo: automaticButton.bottomAnchor, constant: 7),
            promptScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            promptScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            promptHeight,
            contextLabel.topAnchor.constraint(equalTo: promptScroll.bottomAnchor, constant: 9),
            contextLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            contextLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            quoteScroll.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 2),
            quoteScroll.leadingAnchor.constraint(equalTo: promptScroll.leadingAnchor),
            quoteScroll.trailingAnchor.constraint(equalTo: promptScroll.trailingAnchor),
            quoteScroll.heightAnchor.constraint(equalToConstant: 63),
            line.topAnchor.constraint(equalTo: quoteScroll.bottomAnchor, constant: 5),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            chatScroll.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 5),
            chatScroll.leadingAnchor.constraint(equalTo: promptScroll.leadingAnchor),
            chatScroll.trailingAnchor.constraint(equalTo: promptScroll.trailingAnchor),
            chatScroll.bottomAnchor.constraint(equalTo: input.topAnchor, constant: -8),
            input.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            input.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            input.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -7),
            question.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = autoExplain ? "书问 ●" : "书问"
        statusItem.button?.toolTip = "读书提问：在 Mac 图书中划选即可提问"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示读书提问", action: #selector(openWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "词本", action: #selector(openWordbook), keyEquivalent: "").target = self
        menu.addItem(withTitle: "记录划词问题并打开日志", action: #selector(reportSelectionIssue), keyEquivalent: "").target = self
        automaticMenu = NSMenuItem(title: "自动解释", action: #selector(toggleAutomatic), keyEquivalent: "")
        automaticMenu.target = self
        automaticMenu.state = autoExplain ? .on : .off
        menu.addItem(automaticMenu)
        menu.addItem(withTitle: "授权划词", action: #selector(requestAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    @objc func toggleAutomatic() {
        panelController.userInteracted()
        autoExplain.toggle()
        ReadingPreferences.automatic = autoExplain
        automaticButton.state = autoExplain ? .on : .off
        automaticMenu?.state = autoExplain ? .on : .off
        statusItem?.button?.title = autoExplain ? "书问 ●" : "书问"
        if !autoExplain, activeRequestIsAutomatic { stop() }
        status.stringValue = autoExplain ? "自动解释已开启 · 下次划选时发送提示词" : readyStatus
        record(["event": "automatic_changed", "automatic": autoExplain])
    }

    @objc func toggleAutoDismiss() {
        let enabled = autoDismissButton.state == .on
        ReadingPreferences.autoDismiss = enabled
        panelController.setAutomaticDismissal(enabled)
        record(["event": "auto_dismiss_changed", "enabled": enabled, "delaySeconds": ReadingPanelController.delay])
    }

    func textDidChange(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView, editor === promptEditor else { return }
        panelController.userInteracted()
        ReadingPreferences.prompt = editor.string
        if activeTask == nil {
            status.stringValue = editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "提示词为空 · 填写后才能自动解释" : "提示词已保存 · 下次划选时生效"
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field === question {
            panelController.userInteracted()
        }
    }

    @objc func togglePromptEditor() {
        panelController.userInteracted()
        promptExpanded.toggle()
        promptScroll.isHidden = !promptExpanded
        promptHeight.constant = promptExpanded ? 100 : 0
        promptDisclosure.title = promptExpanded ? "收起提示词" : "编辑提示词"
        promptDisclosure.image = NSImage(systemSymbolName: promptExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeFirstResponder(promptExpanded ? promptEditor : question)
    }

    @objc func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        status.stringValue = trusted ? readyStatus : "请在系统设置 → 隐私与安全性 → 辅助功能中开启「读书提问」"
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func captureBooksSelection() {
        let trusted = AXIsProcessTrusted()
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
        if selectionInteraction.observe(buttons: mouseButtons) {
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
        let state = "\(autoExplain):\(trusted):\(booksFrontmost)"
        if state != monitorState {
            monitorState = state
            record(["event": "selection_monitor_state", "enabled": true, "automatic": autoExplain, "accessibilityTrusted": trusted, "booksInForeground": booksFrontmost])
            if selectedText.isEmpty, trusted { status.stringValue = readyStatus }
        }
        guard !selectionReadInProgress, AXIsProcessTrusted(),
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
                guard let selected else { return }
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
    func scheduleCopyCapture(mouseUp: NSEvent) {
        guard copyCaptureEnabled, AXIsProcessTrusted(),
              let books = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first else { return }
        let pid = books.processIdentifier
        let captureID = UUID().uuidString
        let gestureRevision = interactionRevision
        let placement = ReadingPanelPlacement.capture(mouseUp: mouseUp, booksPID: pid)
        pendingCaptureWork?.cancel()
        // Assigning the active ID invalidates any older transaction; its wait loop
        // observes the mismatch and runs its own cleanup before ours starts.
        activeCaptureID = captureID
        DiagnosticLog.shared.record(["event": "copy_capture_scheduled", "captureID": captureID,
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
        let valid = copyCaptureEnabled && AXIsProcessTrusted() && books?.processIdentifier == pid
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
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishCopyCapture(outcome, pid: pid, placement: placement) }
            }
        }
    }

    func finishCopyCapture(_ outcome: CaptureOutcome, pid: pid_t, placement: ReadingPanelPlacement?) {
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
            guard text != selectedText else {
                DiagnosticLog.shared.record(["event": "copy_capture_duplicate", "captureID": outcome.captureID])
                // A confirmed new gesture on the same word restores the current
                // conversation/draft without another paid request. Polling never
                // reaches this branch.
                showWindow(reason: "repeat_selection")
                return
            }
            lastCopyAccepted = text
            // sampleID carries the captureID so history rows correlate with the
            // capture diagnostics for the same selection.
            receive(text, sampleID: "copy-" + outcome.captureID, placement: placement)
        } else {
            // Failure state is shown but never fronts the window and never falls
            // back to AX text or a previous selection.
            status.stringValue = "未能获取选中文字（\(outcome.rejection?.rawValue ?? "unknown")），请重试"
        }
    }

    func refreshBooksConnection() {
        DiagnosticLog.shared.record(["event": "books_connection_refresh", "lastFullScreen": lastBooksFullScreen as Any? ?? "unknown"])
        selectionEventElement = nil
        recentSelectionEvent = .distantPast
        if AXIsProcessTrusted(), let books = NSRunningApplication.runningApplications(withBundleIdentifier: BooksSelection.bundleID).first {
            attachBooksObserver(pid: books.processIdentifier)
        }
    }

    func attachBooksObserver(pid: pid_t) {
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
        if wordbook == nil { wordbook = WordbookWindow(fallbackBook: config?.bookTitle ?? "图书") }
        wordbook?.open()
    }
    /// Fronts the panel. Per the window contract this may only happen for a genuine
    /// new selection or an explicit user open — never from streaming, polling,
    /// answer-completion or capture-failure paths, which is why `reason` is logged.
    func showWindow(reason: String) {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        let selectedScreen = currentPlacement?.displayID.flatMap { id in
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        }
        let screen = selectedScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            let origin = currentPlacement?.origin(in: visible, panelSize: panel.frame.size)
                ?? NSPoint(x: max(visible.minX, visible.maxX - panel.frame.width),
                           y: max(visible.minY, visible.maxY - panel.frame.height))
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(question)
        panelController.didPresent(forSelection: reason == "new_selection" || reason == "repeat_selection")
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

    func receive(_ text: String, sampleID: String, placement: ReadingPanelPlacement? = nil) {
        stop()
        currentPlacement = placement
        currentSampleID = sampleID
        selectedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedText.count <= 6000 else {
            showWindow(reason: "new_selection")
            status.stringValue = "选区较长，请选择 6000 字符以内的一小段。"
            selectedText = ""
            return
        }
        sessionId = UUID().uuidString
        currentRequestID = ""
        messages = []
        displayHistory = ""
        quote.string = selectedText
        transcript.string = ""
        question.stringValue = ""
        do {
            config = try Configuration.load()
            guard let config else { return }
            let paragraphs = try JSONDecoder().decode([BookParagraph].self, from: Data(contentsOf: URL(fileURLWithPath: config.contextFile)))
            context = ReadingContext.match(selectedText, in: paragraphs)
            contextLabel.stringValue = "\(config.bookTitle) · \(context.status)"
        } catch {
            context = ContextMatch(paragraphs: [], status: "本地上下文不可用，仅使用选中文字")
            contextLabel.stringValue = context.status
        }
        record(["event": "selection_received", "selection": selectedText, "bookTitle": config?.bookTitle ?? "图书", "contextIDs": context.paragraphs.map(\.id)])
        showWindow(reason: "new_selection")
        status.stringValue = "选区已就绪 · 输入问题或留空发送模板"
        if autoExplain {
            let prompt = promptEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty { status.stringValue = "选区已就绪 · 请先填写上方提示词" }
            else { ask(prompt, automatic: true) }
        }
    }

    @objc func sendOrStop() {
        panelController.userInteracted()
        if activeTask != nil { stop() }
        else { sendQuestion() }
    }

    @objc func sendQuestion() {
        panelController.userInteracted()
        guard activeTask == nil, !selectedText.isEmpty else { return }
        let value = question.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = value.isEmpty ? promptEditor.string.trimmingCharacters(in: .whitespacesAndNewlines) : value
        guard !prompt.isEmpty else {
            status.stringValue = "请填写问题或上方提示词"
            return
        }
        question.stringValue = ""
        ask(prompt)
    }
    @objc func stop() {
        let wasActive = activeTask != nil
        activeGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        activeRequestIsAutomatic = false
        setBusy(false)
        if wasActive {
            transcript.string = displayHistory + "\n\n已停止本次回答，可以重新提问。"
            status.stringValue = "已停止"
            record(["event": "cancelled"])
        }
    }
    func setBusy(_ busy: Bool) {
        sendButton?.title = busy ? "停止" : "发送"
        sendButton?.setAccessibilityLabel(busy ? "停止回答" : "发送")
    }

    func ask(_ prompt: String, automatic: Bool = false) {
        guard activeTask == nil, !selectedText.isEmpty, let config else { return }
        activeRequestIsAutomatic = automatic
        currentRequestID = UUID().uuidString
        record(["event": "request_started", "automatic": automatic, "question": prompt,
                "selection": selectedText, "displayedSelection": quote.string, "model": config.model,
                "contextIDs": context.paragraphs.map(\.id)])
        let generation = UUID()
        activeGeneration = generation
        let selection = selectedText
        let match = context
        let previous = messages
        let heading = (previous.isEmpty ? "" : "\n\n") + (automatic ? "" : "你：\(prompt)\n\n")
        let prefix = displayHistory + heading
        transcript.string = prefix + "正在思考…"
        status.stringValue = "\(config.model) · 正在连接"
        setBusy(true)
        let started = Date()
        activeTask = Task { @MainActor in
            var key = ""
            var answer = ""
            do {
                key = try config.credential()
                DiagnosticLog.shared.registerSecret(key)
                let system = ReadingPreferences.systemPrompt
                let contextText = match.paragraphs.map(\.text).joined(separator: "\n\n")
                let initial = "书名：\(config.bookTitle)\n选中文字：\n<selection>\n\(selection)\n</selection>\n上下文匹配状态：\(match.status)\n<book_context>\n\(contextText)\n</book_context>"
                let bodyMessages = [["role": "system", "content": system], ["role": "user", "content": initial]] + previous + [["role": "user", "content": prompt]]
                guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else { throw URLError(.badURL) }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 90
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["model": config.model, "messages": bodyMessages, "stream": true, "max_tokens": 1800])
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard generation == activeGeneration else { return }
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                record(["event": "response_headers", "httpStatus": http.statusCode,
                        "elapsedSeconds": Date().timeIntervalSince(started)])
                guard http.statusCode == 200 else {
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 1200 { break }
                    }
                    throw NSError(domain: "BookAsk", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "模型服务返回 HTTP \(http.statusCode)：\(errorBody)"])
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
                    if let serverError = value["error"] { throw NSError(domain: "BookAsk", code: 2, userInfo: [NSLocalizedDescriptionKey: "模型服务错误：\(serverError)"]) }
                    if let choices = value["choices"] as? [[String: Any]], let reason = choices.first?["finish_reason"] as? String { finishReason = reason }
                    if let choices = value["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any], let text = delta["content"] as? String, !text.isEmpty {
                        answer += text
                        if !receivedContent {
                            record(["event": "first_content", "elapsedSeconds": Date().timeIntervalSince(started)])
                            receivedContent = true
                        }
                        transcript.string = prefix + answer
                        transcript.scrollToEndOfDocument(nil)
                        status.stringValue = "\(config.model) · 正在回答"
                    }
                }
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                guard completedStream else { throw NSError(domain: "BookAsk", code: 4, userInfo: [NSLocalizedDescriptionKey: "连接提前结束，回答未完整接收。"] ) }
                guard finishReason != "length" else { throw NSError(domain: "BookAsk", code: 5, userInfo: [NSLocalizedDescriptionKey: "回答达到长度限制，尚未完整生成，请缩小问题范围。"] ) }
                guard !answer.isEmpty else { throw NSError(domain: "BookAsk", code: 3, userInfo: [NSLocalizedDescriptionKey: "模型没有返回文本，请重试。"] ) }
                messages = previous + [["role": "user", "content": prompt], ["role": "assistant", "content": answer]]
                displayHistory = prefix + answer
                status.stringValue = "\(config.model) · 已完成 · 可继续追问"
                record(["event": "answer", "model": config.model, "selection": selection, "question": prompt, "answer": answer,
                        "elapsedSeconds": Date().timeIntervalSince(started), "contextIDs": match.paragraphs.map(\.id), "turn": messages.count / 2])
            } catch {
                guard generation == activeGeneration else { return }
                let errorText = key.isEmpty ? error.localizedDescription : error.localizedDescription.replacingOccurrences(of: key, with: "[REDACTED]")
                transcript.string = prefix + (answer.isEmpty ? "" : answer + "\n\n") + "请求未完成：\(errorText)\n可在输入框留空时点击「发送」重试。"
                status.stringValue = "请求未完成"
                record(["event": "error", "message": errorText])
            }
            if generation == activeGeneration {
                activeTask = nil
                activeRequestIsAutomatic = false
                setBusy(false)
                if panel.isVisible && panel.isKeyWindow { panel.makeFirstResponder(question) }
            }
        }
    }

    func record(_ fields: [String: Any]) {
        var value = fields
        value["sessionID"] = sessionId
        value["sampleID"] = value["sampleID"] ?? currentSampleID
        value["requestID"] = currentRequestID
        value["runID"] = DiagnosticLog.shared.runID
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
               wordbook?.window?.isVisible == true { wordbook?.reload() }
        } catch {
            DiagnosticLog.shared.record(["event": "history_write_failed", "message": error.localizedDescription])
            status?.stringValue = "本地记录写入失败，请从菜单记录问题"
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = MainActor.assumeIsolated { BookAsk() }
application.delegate = delegate
application.run()
