import AppKit
import ApplicationServices

/// One guarded Books-copy transaction. The pre-existing clipboard is held only in
/// memory; its contents are never logged, persisted, or sent to the model.
/// Contract: deltas/books_selection_copy_and_focus/RFC.md 「剪贴板事务」.

protocol PasteboardAccess {
    var changeCount: Int { get }
    /// Full in-memory copy of every item and type. Returns nil when any type's data
    /// cannot be materialized; the caller must then skip the copy action entirely.
    func snapshot() -> ClipboardSnapshot?
    /// Metadata only: backend and failure location, never clipboard payloads.
    var snapshotDiagnostics: [String: Any] { get }
    /// Writes the snapshot back. Returns changeCount, or -1 on write failure.
    @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int
    func firstString() -> String?
}

extension PasteboardAccess {
    var snapshotDiagnostics: [String: Any] { [:] }
}

struct ClipboardSnapshot {
    /// One entry per pasteboard item: pasteboard type -> materialized bytes.
    let items: [[String: Data]]
    let changeCount: Int
    /// Present only when a legacy format required the Pasteboard compatibility
    /// API. Keep each item's original format order for restoration.
    var legacyTypeOrder: [[String]]? = nil
    var typeCount: Int { items.reduce(0) { $0 + $1.count } }
    var byteCount: Int { items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
}

final class SystemPasteboard: PasteboardAccess {
    /// Defaults to the general pasteboard; tests inject a uniquely named
    /// pasteboard so real NSPasteboard semantics are exercised without
    /// touching the user's clipboard.
    private let pasteboard: NSPasteboard
    private(set) var snapshotDiagnostics: [String: Any] = [:]
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> ClipboardSnapshot? {
        let current = changeCount
        snapshotDiagnostics = ["snapshotBackend": "appkit"]
        var items: [[String: Data]] = []
        var typeOrder: [[String]] = []
        var rawBoard: Pasteboard?
        var usedLegacy = false
        let sourceItems = pasteboard.pasteboardItems ?? []
        for (index, item) in sourceItems.enumerated() {
            var entry: [String: Data] = [:]
            for type in item.types {
                // Materializes delayed/promised data; a missing value means the
                // clipboard cannot be fully backed up, so the transaction is refused.
                var data = item.data(forType: type)
                if data == nil {
                    // Qt/WeChat names can contain underscores: AppKit advertises
                    // them, then rejects them as UTIs. The public Pasteboard API
                    // accepts these existing names. Match the item, not the first
                    // global occurrence of a type (which can belong to another item).
                    if rawBoard == nil { rawBoard = compatibilityBoard() }
                    var status: OSStatus = -1
                    if let raw = rawBoard {
                        var count = 0
                        status = PasteboardGetItemCount(raw, &count)
                        if status == noErr && count == sourceItems.count {
                            var identifier: PasteboardItemID?
                            status = PasteboardGetItemIdentifier(raw, index + 1, &identifier)
                            if status == noErr, let identifier = identifier {
                                var bytes: CFData?
                                status = PasteboardCopyItemFlavorData(raw, identifier, type.rawValue as CFString, &bytes)
                                if status == noErr, let bytes = bytes { data = bytes as Data }
                            }
                        }
                    }
                    guard data != nil else {
                        snapshotDiagnostics["snapshotFailureItem"] = index
                        snapshotDiagnostics["snapshotFailureType"] = String(type.rawValue.prefix(200))
                        snapshotDiagnostics["snapshotFailureStatus"] = status
                        return nil
                    }
                    usedLegacy = true
                    snapshotDiagnostics["snapshotBackend"] = "appkit_with_legacy_formats"
                }
                guard let data = data else { return nil }
                entry[type.rawValue] = data
            }
            items.append(entry)
            typeOrder.append(item.types.map(\.rawValue))
        }
        guard changeCount == current else {
            snapshotDiagnostics["snapshotGenerationChanged"] = true
            return nil
        }
        var result = ClipboardSnapshot(items: items, changeCount: current)
        if usedLegacy { result.legacyTypeOrder = typeOrder }
        return result
    }

    /// Each reference is confined to the serial capture transaction; these APIs
    /// must not be used concurrently through a shared Pasteboard reference.
    private func compatibilityBoard() -> Pasteboard? {
        let name = pasteboard.name == .general ? kPasteboardClipboard : pasteboard.name.rawValue
        var board: Pasteboard?
        guard PasteboardCreate(name as CFString, &board) == noErr, let board = board else { return nil }
        PasteboardSynchronize(board)
        return board
    }

    @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int {
        if let order = snapshot.legacyTypeOrder {
            guard order.count == snapshot.items.count,
                  zip(order, snapshot.items).allSatisfy({ Set($0.0) == Set($0.1.keys) }),
                  let raw = compatibilityBoard() else { return -1 }
            guard PasteboardClear(raw) == noErr else { return -1 }
            for (index, types) in order.enumerated() {
                let identifier = PasteboardItemID(bitPattern: index + 1)!
                for type in types {
                    guard let data = snapshot.items[index][type],
                          PasteboardPutItemFlavor(raw, identifier, type as CFString, data as CFData, []) == noErr
                    else { return -1 }
                }
            }
            return changeCount
        }
        var restored: [NSPasteboardItem] = []
        for entry in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in entry {
                guard item.setData(data, forType: NSPasteboard.PasteboardType(type)) else { return -1 }
            }
            restored.append(item)
        }
        pasteboard.clearContents()
        if !restored.isEmpty, !pasteboard.writeObjects(restored) { return -1 }
        return changeCount
    }

    func firstString() -> String? { pasteboard.string(forType: .string) }
}

/// Books wraps copied text with a citation block. Only these two fully-anchored,
/// previously observed formats are stripped; anything similar but unmatched is
/// ambiguous and must not be silently trimmed.
enum BooksExcerptStrip {
    enum Result: Equatable {
        case stripped(String)
        case noWrapper
        case ambiguous
    }

    // The excerpt body may span lines; `.` alone would reject every multi-line
    // selection as ambiguous, so the body group explicitly includes newlines.
    private static let englishPattern = #"\A“([\s\S]+?)”\s+Excerpt From[\s\S]+?This material may be protected by copyright\.\s*\z"#
    private static let chinesePattern = #"\A“([\s\S]+?)”\s+摘[\s\S]+?此材料受版权保护。\s*\z"#
    private static let markers = ["Excerpt From", "此材料受版权保护"]

    static func strip(_ text: String) -> Result {
        for pattern in [englishPattern, chinesePattern] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let body = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return body.isEmpty ? .ambiguous : .stripped(body)
            }
        }
        return markers.contains(where: { text.contains($0) }) ? .ambiguous : .noWrapper
    }
}

enum CaptureRejection: String {
    case snapshotIncomplete = "snapshot_incomplete"
    case snapshotChanged = "snapshot_changed"
    case restoreFailed = "restore_failed"
    case copyUnavailable = "copy_unavailable"
    case timeout = "copy_timeout"
    case ambiguousWrites = "ambiguous_writes"
    case externalWriteBeforeRead = "external_write_before_read"
    case emptyResult = "empty_result"
    case tooLong = "too_long"
    case wrapperAmbiguous = "wrapper_ambiguous"
    case cancelled = "cancelled"
}

struct CaptureOutcome {
    enum Phase: String {
        case eligible, snapshot, copyIssued, captured, restoreOrPreserveNew, accepted, rejected
    }
    let captureID: String
    let strategy: String
    var phase: Phase = .eligible
    var acceptedText: String?
    var rejection: CaptureRejection?
    var wrapper = "n/a"
    var issueMethod = "none"
    var baselineCount = -1
    var capturedCount = -1
    var finalCount = -1
    var snapshotItems = 0
    var snapshotTypes = 0
    var snapshotBytes = 0
    var restored = false
    var preservedNew = false
    var polls = 0
    var elapsedMS = 0
    var snapshotReadDetails: [String: Any] = [:]

    /// Diagnostics-safe fields: counts and phases only, never clipboard contents.
    func logFields() -> [String: Any] {
        var fields: [String: Any] = ["captureID": captureID, "strategy": strategy, "phase": phase.rawValue,
         "rejection": rejection?.rawValue ?? "", "wrapper": wrapper, "issueMethod": issueMethod,
         "baselineCount": baselineCount, "capturedCount": capturedCount, "finalCount": finalCount,
         "snapshotItems": snapshotItems, "snapshotTypes": snapshotTypes, "snapshotBytes": snapshotBytes,
         "restored": restored, "preservedNew": preservedNew, "polls": polls, "elapsedMS": elapsedMS,
         "acceptedLength": acceptedText?.count ?? 0]
        fields.merge(snapshotReadDetails) { existing, _ in existing }
        return fields
    }
}

enum CopyCapture {
    /// Provisional values; T01 real-machine measurements may adjust them in the RFC.
    static var settleDelay: Double = 0.25
    static var pollInterval: Double = 0.01
    static var timeout: Double = 0.8
    static var maxSelectionLength = 6000

    /// Runs one full transaction on the caller's thread. `issue` performs exactly
    /// one copy action (menu press or targeted ⌘C) and reports whether any action
    /// was possible; it must never retry by itself. `preRestoreHook` exists only so
    /// deterministic tests can inject a racing write at the exact restore window.
    static func run(pasteboard: PasteboardAccess,
                    captureID: String,
                    strategy: String = "books_copy",
                    issue: (inout CaptureOutcome) -> Bool,
                    isCancelled: () -> Bool = { false },
                    now: () -> Double = { ProcessInfo.processInfo.systemUptime },
                    sleep: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                    preRestoreHook: (() -> Void)? = nil) -> CaptureOutcome {
        let started = now()
        var outcome = CaptureOutcome(captureID: captureID, strategy: strategy)
        func finish(_ phase: CaptureOutcome.Phase) -> CaptureOutcome {
            outcome.phase = phase
            outcome.elapsedMS = Int((now() - started) * 1000)
            return outcome
        }
        // eligible → snapshot
        outcome.baselineCount = pasteboard.changeCount
        let snapshot = pasteboard.snapshot()
        outcome.snapshotReadDetails = pasteboard.snapshotDiagnostics
        guard let snapshot = snapshot else {
            outcome.rejection = .snapshotIncomplete
            outcome.finalCount = pasteboard.changeCount
            return finish(.rejected)
        }
        outcome.phase = .snapshot
        outcome.baselineCount = snapshot.changeCount
        outcome.snapshotItems = snapshot.items.count
        outcome.snapshotTypes = snapshot.typeCount
        outcome.snapshotBytes = snapshot.byteCount
        // Materializing a delayed provider can take time. Never overwrite a copy
        // made while the snapshot was being read or before our action begins.
        guard pasteboard.changeCount == snapshot.changeCount else {
            outcome.rejection = .snapshotChanged
            outcome.preservedNew = true
            outcome.finalCount = pasteboard.changeCount
            return finish(.rejected)
        }
        guard !isCancelled() else {
            outcome.rejection = .cancelled
            return finish(.rejected)
        }
        // snapshot → copyIssued (exactly one action; a later timeout never re-issues)
        guard issue(&outcome) else {
            outcome.rejection = .copyUnavailable
            return finish(.rejected)
        }
        outcome.phase = .copyIssued
        // copyIssued → captured: wait for exactly one new clipboard generation
        let deadline = started + timeout
        var captured: String?
        while now() < deadline {
            if isCancelled() {
                outcome.rejection = .cancelled
                restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
                return finish(.rejected)
            }
            let count = pasteboard.changeCount
            if count == snapshot.changeCount {
                outcome.polls += 1
                sleep(pollInterval)
                continue
            }
            guard count == snapshot.changeCount + 1 else {
                // The clipboard moved more than one generation without us observing
                // the intermediate write: the writer cannot be proven. Refuse the
                // result and keep the newest external content.
                outcome.rejection = .ambiguousWrites
                outcome.finalCount = count
                outcome.preservedNew = true
                return finish(.rejected)
            }
            let text = pasteboard.firstString()
            guard pasteboard.changeCount == count else {
                outcome.rejection = .externalWriteBeforeRead
                outcome.finalCount = pasteboard.changeCount
                outcome.preservedNew = true
                return finish(.rejected)
            }
            captured = text
            outcome.capturedCount = count
            break
        }
        guard let text = captured else {
            outcome.rejection = isCancelled() ? .cancelled : .timeout
            // A write that landed exactly at the deadline or just before a cancel is
            // still this transaction's own copy: restore the snapshot rather than
            // leave a Books excerpt behind. Absent or multiplied writes are left
            // untouched, because their writer cannot be proven.
            restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
            return finish(.rejected)
        }
        outcome.phase = .captured
        // Validate and unwrap before touching the restore phase.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        switch BooksExcerptStrip.strip(trimmed) {
        case .stripped(let unwrapped): outcome.wrapper = "stripped"; body = unwrapped
        case .noWrapper: outcome.wrapper = "absent"; body = trimmed
        case .ambiguous:
            outcome.wrapper = "ambiguous"
            outcome.rejection = .wrapperAmbiguous
            restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
            return finish(.rejected)
        }
        if body.isEmpty {
            outcome.rejection = .emptyResult
            restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
            return finish(.rejected)
        }
        if body.count > maxSelectionLength {
            outcome.rejection = .tooLong
            restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
            return finish(.rejected)
        }
        preRestoreHook?()
        restoreIfOurs(pasteboard, snapshot: snapshot, outcome: &outcome)
        guard outcome.rejection == nil else { return finish(.rejected) }
        guard !isCancelled() else {
            outcome.rejection = .cancelled
            return finish(.rejected)
        }
        outcome.acceptedText = body
        return finish(.accepted)
    }

    /// captured/cancelled → restoreOrPreserveNew: restore only while the clipboard
    /// still holds exactly this transaction's result; newer external content wins.
    private static func restoreIfOurs(_ pasteboard: PasteboardAccess,
                                      snapshot: ClipboardSnapshot,
                                      outcome: inout CaptureOutcome) {
        let current = pasteboard.changeCount
        // This transaction's own write is the observed capture generation, or —
        // when a cancel/timeout raced a copy that had already landed — the single
        // generation after the baseline.
        let expected = outcome.capturedCount >= 0 ? outcome.capturedCount : snapshot.changeCount + 1
        guard current == expected else {
            outcome.finalCount = current
            outcome.preservedNew = current != snapshot.changeCount
            outcome.phase = .restoreOrPreserveNew
            return
        }
        outcome.phase = .restoreOrPreserveNew
        // restore() itself performs clearContents + writeObjects, which may advance
        // changeCount by more than one; any advance here is our own restore write.
        let after = pasteboard.restore(snapshot)
        outcome.restored = after > current
        outcome.finalCount = pasteboard.changeCount
        if !outcome.restored { outcome.rejection = .restoreFailed }
    }
}

/// The copy channel never falls back to AX text: a failed or ambiguous copy means
/// no selection is delivered at all, even when AX offers a non-empty word.
enum CaptureDecision {
    static func selection(copyEnabled: Bool, outcome: CaptureOutcome, axText: String?) -> String? {
        copyEnabled ? outcome.acceptedText : axText
    }
}
