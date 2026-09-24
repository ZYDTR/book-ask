import AppKit
import ApplicationServices

/// Deterministic tests for the guarded Books-copy transaction (T02 decision rules,
/// T03 snapshot/restore fidelity, T04 race & cancellation protection, T05 gesture
/// gating). Mock pasteboards make the scheduling deterministic; one section uses a
/// real, uniquely named NSPasteboard to exercise genuine snapshot/restore bytes
/// without touching the user's general pasteboard.

final class MockPasteboard: PasteboardAccess {
    var items: [[String: Data]]
    var count: Int
    var failSnapshot = false
    var failRestore = false
    var onFirstString: (() -> Void)?
    var onSnapshot: (() -> Void)?
    init(text: String = "original", count: Int = 5) {
        self.items = [["public.utf8-plain-text": Data(text.utf8)]]
        self.count = count
    }
    var changeCount: Int { count }
    func snapshot() -> ClipboardSnapshot? {
        guard !failSnapshot else { return nil }
        let saved = ClipboardSnapshot(items: items, changeCount: count)
        onSnapshot?()
        return saved
    }
    @discardableResult func restore(_ snapshot: ClipboardSnapshot) -> Int {
        if failRestore { count += 1; items = []; return -1 }
        items = snapshot.items
        count += 2 // clearContents + writeObjects
        return count
    }
    func firstString() -> String? {
        onFirstString?()
        return items.first?["public.utf8-plain-text"].map { String(decoding: $0, as: UTF8.self) }
    }
    func write(_ text: String) {
        items = [["public.utf8-plain-text": Data(text.utf8)]]
        count += 1
    }
    var string: String? { items.first?["public.utf8-plain-text"].map { String(decoding: $0, as: UTF8.self) } }
}

func check(_ value: Bool, _ name: String) {
    if !value { fputs("FAIL: \(name)\n", stderr); exit(1) }
}

@main struct ClipboardCaptureTests {
    static func main() {
        // ---------- T02: decision rules ----------
        var accepted = CaptureOutcome(captureID: "d1", strategy: "books_copy")
        accepted.acceptedText = "bulldozer"
        accepted.phase = .accepted
        var rejected = CaptureOutcome(captureID: "d2", strategy: "books_copy")
        rejected.phase = .rejected
        rejected.rejection = .timeout
        check(CaptureDecision.selection(copyEnabled: true, outcome: accepted, axText: "er, forci") == "bulldozer",
              "copy result wins over a non-empty wrong AX word")
        check(CaptureDecision.selection(copyEnabled: true, outcome: rejected, axText: "er, forci") == nil,
              "failed copy never falls back to AX text")
        check(CaptureDecision.selection(copyEnabled: false, outcome: rejected, axText: "word") == "word",
              "strategy off keeps the read-only AX path")

        // ---------- BooksExcerptStrip ----------
        let english = "“bulldozer”\n\nExcerpt From\nThe Mom Test\nFitzpatrick, Rob\nThis material may be protected by copyright."
        check(BooksExcerptStrip.strip(english) == .stripped("bulldozer"), "english wrapper stripped")
        let multiLine = "“第一段。\n\n第二段。”\n\nExcerpt From\nThe Mom Test\nThis material may be protected by copyright."
        check(BooksExcerptStrip.strip(multiLine) == .stripped("第一段。\n\n第二段。"), "multi-line selection inside wrapper is stripped, not rejected")
        let chinese = "“这只狗在追猫”\n\n摘\n某书\n此材料受版权保护。"
        check(BooksExcerptStrip.strip(chinese) == .stripped("这只狗在追猫"), "chinese wrapper stripped")
        check(BooksExcerptStrip.strip("plain selection") == .noWrapper, "plain text has no wrapper")
        check(BooksExcerptStrip.strip("正文提到 Excerpt From 但包装不完整") == .ambiguous,
              "marker-like text without a full wrapper is ambiguous, never trimmed")
        check(BooksExcerptStrip.strip("”\n\nExcerpt From\nX\nThis material may be protected by copyright.") == .ambiguous,
              "unmatched wrapper shape is ambiguous")

        // ---------- run(): accept + restore ----------
        let pb1 = MockPasteboard()
        var issueCalls = 0
        let ok = CopyCapture.run(pasteboard: pb1, captureID: "c1", issue: { _ in issueCalls += 1; pb1.write("bulldozer"); return true }, sleep: { _ in })
        check(ok.phase == .accepted && ok.acceptedText == "bulldozer", "accept captured selection")
        check(ok.restored && !ok.preservedNew && pb1.string == "original", "original clipboard restored after accept")
        check(ok.baselineCount == 5 && ok.capturedCount == 6 && ok.finalCount == 8, "changeCount stages recorded")
        check(issueCalls == 1, "exactly one copy action per transaction")
        check(ok.snapshotItems == 1 && ok.snapshotTypes == 1 && ok.snapshotBytes > 0, "snapshot statistics logged, not contents")

        // wrapped copy result
        let pb2 = MockPasteboard()
        let wrapped = CopyCapture.run(pasteboard: pb2, captureID: "c2", issue: { _ in pb2.write(english); return true }, sleep: { _ in })
        check(wrapped.phase == .accepted && wrapped.acceptedText == "bulldozer" && wrapped.wrapper == "stripped",
              "wrapper removed before delivery")

        // empty / too long / ambiguous wrapper results are rejected and restored
        let pb3 = MockPasteboard()
        let empty = CopyCapture.run(pasteboard: pb3, captureID: "c3", issue: { _ in pb3.write("   \n "); return true }, sleep: { _ in })
        check(empty.rejection == .emptyResult && empty.restored && pb3.string == "original", "empty result rejected and restored")
        let pb4 = MockPasteboard()
        let long = CopyCapture.run(pasteboard: pb4, captureID: "c4", issue: { _ in pb4.write(String(repeating: "x", count: 7000)); return true }, sleep: { _ in })
        check(long.rejection == .tooLong && long.restored, "overlong result rejected and restored")
        let pb5 = MockPasteboard()
        let amb = CopyCapture.run(pasteboard: pb5, captureID: "c5", issue: { _ in pb5.write("正文 Excerpt From 残缺包装"); return true }, sleep: { _ in })
        check(amb.rejection == .wrapperAmbiguous && amb.restored, "ambiguous wrapper rejected and restored")

        // ---------- run(): failure & race protection (T04) ----------
        // timeout: copy never lands, clipboard untouched, exactly one issue
        let pb6 = MockPasteboard()
        var t6 = 0.0
        issueCalls = 0
        let timeout = CopyCapture.run(pasteboard: pb6, captureID: "c6",
            issue: { _ in issueCalls += 1; return true },
            now: { t6 += 0.1; return t6 }, sleep: { _ in })
        check(timeout.rejection == .timeout && issueCalls == 1, "timeout issues exactly one copy action")
        check(!timeout.restored && !timeout.preservedNew && pb6.string == "original" && pb6.changeCount == 5,
              "timeout with no write leaves the clipboard untouched")

        // ambiguous writes: two generations appear without us observing the first
        let pb7 = MockPasteboard()
        let ambiguous = CopyCapture.run(pasteboard: pb7, captureID: "c7", issue: { _ in pb7.write("ours"); pb7.write("external"); return true }, sleep: { _ in })
        check(ambiguous.rejection == .ambiguousWrites && ambiguous.preservedNew && !ambiguous.restored,
              "unexplained extra writes reject the result")
        check(pb7.string == "external", "newest external content is preserved")

        // external write between the count check and the read
        let pb8 = MockPasteboard()
        let raced = CopyCapture.run(pasteboard: pb8, captureID: "c8", issue: { _ in
            pb8.write("ours")
            pb8.onFirstString = { pb8.write("external") }
            return true
        }, sleep: { _ in })
        check(raced.rejection == .externalWriteBeforeRead && raced.preservedNew, "write racing the read rejects the result")

        // snapshot that cannot be fully materialized: no copy is ever issued
        let pb9 = MockPasteboard()
        pb9.failSnapshot = true
        issueCalls = 0
        let noBackup = CopyCapture.run(pasteboard: pb9, captureID: "c9", issue: { _ in issueCalls += 1; return true }, sleep: { _ in })
        check(noBackup.rejection == .snapshotIncomplete && issueCalls == 0 && pb9.string == "original",
              "incomplete backup skips the copy and leaves the clipboard unchanged")

        // The old candidate checked generation only after issuing Copy, so a
        // user's newer copy during snapshot materialization was overwritten.
        let changedSnapshot = MockPasteboard()
        changedSnapshot.onSnapshot = { changedSnapshot.write("new copy during snapshot") }
        issueCalls = 0
        let staleSnapshot = CopyCapture.run(pasteboard: changedSnapshot, captureID: "snapshot-race",
            issue: { _ in issueCalls += 1; changedSnapshot.write("Books result"); return true })
        check(staleSnapshot.rejection == .snapshotChanged && issueCalls == 0,
              "copy is never issued against a stale snapshot")
        check(changedSnapshot.string == "new copy during snapshot", "copy during snapshot is preserved")

        // cancel after our copy landed but before we observed it: restore anyway
        let pb10 = MockPasteboard()
        var issued10 = false
        let cancelled = CopyCapture.run(pasteboard: pb10, captureID: "c10",
            issue: { _ in issued10 = true; pb10.write("ours"); return true },
            isCancelled: { issued10 }, sleep: { _ in })
        check(cancelled.rejection == .cancelled && cancelled.restored && pb10.string == "original",
              "cancel with a landed copy still restores the original clipboard")

        // cancel before the copy landed: nothing to restore
        let pb11 = MockPasteboard()
        let cancelledEarly = CopyCapture.run(pasteboard: pb11, captureID: "c11",
            issue: { _ in true }, isCancelled: { true }, sleep: { _ in })
        check(cancelledEarly.rejection == .cancelled && !cancelledEarly.restored && pb11.string == "original",
              "cancel without a write leaves the clipboard untouched")

        // external write in the exact restore window: selection is delivered, new content wins
        let pb12 = MockPasteboard()
        let raced2 = CopyCapture.run(pasteboard: pb12, captureID: "c12", issue: { _ in pb12.write("bulldozer"); return true },
            sleep: { _ in }, preRestoreHook: { pb12.write("user copied something else") })
        check(raced2.phase == .accepted && raced2.acceptedText == "bulldozer", "valid capture is delivered despite a restore race")
        check(!raced2.restored && raced2.preservedNew && pb12.string == "user copied something else",
              "external content written during the transaction is preserved")

        let cancelledAfterRead = MockPasteboard()
        var lostTarget = false
        let lateCancel = CopyCapture.run(pasteboard: cancelledAfterRead, captureID: "late-cancel",
            issue: { _ in cancelledAfterRead.write("bulldozer"); return true },
            isCancelled: { lostTarget }, preRestoreHook: { lostTarget = true })
        check(lateCancel.rejection == .cancelled && lateCancel.acceptedText == nil && lateCancel.restored,
              "target loss after reading still cleans up and never delivers a stale selection")

        let failedRestore = MockPasteboard()
        failedRestore.failRestore = true
        let restorationError = CopyCapture.run(pasteboard: failedRestore, captureID: "restore-error",
            issue: { _ in failedRestore.write("bulldozer"); return true })
        check(restorationError.rejection == .restoreFailed && restorationError.acceptedText == nil && !restorationError.restored,
              "a failed clipboard write is not reported as a successful restore or delivered to the model")

        // ---------- T03: real NSPasteboard snapshot/restore fidelity ----------
        let real = NSPasteboard(name: NSPasteboard.Name("bookask-test-" + UUID().uuidString))
        real.clearContents()
        let html = Data("<b>rich</b>".utf8)
        let rtf = Data(#"{\rtf1 hi}"#.utf8)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])
        let itemA = NSPasteboardItem()
        itemA.setString("plain text", forType: .string)
        itemA.setData(html, forType: .html)
        let itemB = NSPasteboardItem()
        itemB.setData(png, forType: .png)
        itemB.setData(rtf, forType: .rtf)
        real.writeObjects([itemA, itemB])
        let system = SystemPasteboard(real)
        guard let before = system.snapshot() else { fputs("FAIL: real snapshot\n", stderr); exit(1) }
        check(before.items.count == 2, "multi-item snapshot")
        let realRun = CopyCapture.run(pasteboard: system, captureID: "real1", issue: { _ in
            real.clearContents()
            real.setString("选自图书的文字", forType: .string)
            return true
        }, sleep: { _ in })
        check(realRun.phase == .accepted && realRun.acceptedText == "选自图书的文字", "real pasteboard capture accepted")
        check(realRun.restored, "real pasteboard restore reported")
        guard let after = system.snapshot() else { fputs("FAIL: restore snapshot\n", stderr); exit(1) }
        check(after.items == before.items, "every item, type and byte restored on a real pasteboard")
        // NSPasteboard.string(forType:) concatenates every item's string; the RTF
        // item's translated text proves translated types survive the round trip.
        check(real.string(forType: .string)?.contains("plain text") == true, "original string readable after restore")
        check(real.string(forType: .string)?.contains("hi") == true, "rtf-translated string survives restore")

        // empty clipboard is a legal snapshot and restores cleanly
        let realEmpty = NSPasteboard(name: NSPasteboard.Name("bookask-test-empty-" + UUID().uuidString))
        realEmpty.clearContents()
        let emptySystem = SystemPasteboard(realEmpty)
        let emptyRun = CopyCapture.run(pasteboard: emptySystem, captureID: "real2", issue: { _ in
            realEmpty.clearContents()
            realEmpty.setString("x", forType: .string)
            return true
        }, sleep: { _ in })
        check(emptyRun.phase == .accepted && emptyRun.restored, "empty clipboard snapshot accepted and restored")
        check(emptySystem.firstString() == nil && emptySystem.snapshot()?.items.isEmpty == true,
              "empty clipboard restored to empty")

        // Qt/WeChat publishes legacy names containing underscores. AppKit lists
        // these names but refuses to read/write them as UTIs. Use real named
        // pasteboards and synthetic bytes; never modify the user's clipboard.
        let legacy = NSPasteboard(name: NSPasteboard.Name("bookask-test-legacy-" + UUID().uuidString))
        var rawLegacy: Pasteboard?
        check(PasteboardCreate(legacy.name.rawValue as CFString, &rawLegacy) == noErr, "create legacy fixture")
        let raw = rawLegacy!
        check(PasteboardClear(raw) == noErr, "clear named legacy fixture")
        let legacyType = "com.trolltech.anymime.WeChat_RichEdit_Format"
        let legacyType2 = "com.trolltech.anymime.QQ_Unicode_RichEdit_Format"
        let fixture: [[String: Data]] = [
            [legacyType: Data([0, 1, 255, 10]), legacyType2: Data([7, 0, 8]), "public.utf8-plain-text": Data("first item".utf8)],
            [legacyType: Data([3, 4, 0, 99]), "public.utf8-plain-text": Data("second item".utf8)]
        ]
        for (index, entry) in fixture.enumerated() {
            for (type, data) in entry {
                check(PasteboardPutItemFlavor(raw, PasteboardItemID(bitPattern: index + 1)!, type as CFString,
                                             data as CFData, []) == noErr, "write legacy fixture")
            }
        }
        let legacySystem = SystemPasteboard(legacy)
        let legacyCount = legacy.changeCount
        guard let legacyBefore = legacySystem.snapshot() else {
            fputs("FAIL: complete snapshot of Qt/WeChat legacy formats\n", stderr); exit(1)
        }
        check(legacy.changeCount == legacyCount, "legacy snapshot is read-only")
        check(legacyBefore.items.count == fixture.count, "legacy item boundaries preserved")
        for (index, entry) in fixture.enumerated() {
            for (type, data) in entry {
                check(legacyBefore.items[index][type] == data, "legacy snapshot exact bytes in correct item")
            }
        }
        let legacyRun = CopyCapture.run(pasteboard: legacySystem, captureID: "legacy", issue: { _ in
            legacy.clearContents()
            legacy.setString("bulldozer", forType: .string)
            return true
        })
        check(legacyRun.phase == .accepted && legacyRun.restored, "legacy clipboard permits capture and restoration")
        let legacyAfter = legacySystem.snapshot()
        check(legacyAfter?.items == legacyBefore.items, "all legacy items, types and bytes round-trip")
        check(legacyAfter?.legacyTypeOrder == legacyBefore.legacyTypeOrder, "legacy flavor preference order preserved")
        check(legacyRun.logFields()["snapshotBackend"] as? String == "appkit_with_legacy_formats",
              "compatibility backend recorded without clipboard payloads")
        check(legacy.string(forType: .string)?.contains("second item") == true, "restored legacy plain text usable")
        legacy.releaseGlobally()

        // ---------- T05: gesture gating ----------
        check(BooksCopy.isSelectionGesture(dragged: true, clickCount: 1, button: 0), "drag selection issues a copy")
        check(BooksCopy.isSelectionGesture(dragged: false, clickCount: 2, button: 0), "double click issues a copy")
        check(BooksCopy.isSelectionGesture(dragged: false, clickCount: 3, button: 0), "triple click issues a copy")
        check(!BooksCopy.isSelectionGesture(dragged: false, clickCount: 1, button: 0), "plain click never copies")
        check(!BooksCopy.isSelectionGesture(dragged: false, clickCount: 0, button: 0), "poll ticks never copy")
        check(!BooksCopy.isSelectionGesture(dragged: true, clickCount: 1, button: 1), "right-button drags never copy")

        // ---------- diagnostics shape (T09 fields) ----------
        let fields = ok.logFields()
        for key in ["captureID", "strategy", "phase", "rejection", "wrapper", "issueMethod",
                    "baselineCount", "capturedCount", "finalCount", "snapshotItems", "snapshotTypes",
                    "snapshotBytes", "restored", "preservedNew", "polls", "elapsedMS", "acceptedLength"] {
            check(fields.keys.contains(key), "log field \(key) present")
        }
        check(fields["captureID"] as? String == "c1" && fields["strategy"] as? String == "books_copy",
              "outcome carries correlation IDs")

        print("PASS: copy capture transaction, decision rules, excerpt stripping, real pasteboard fidelity, race/cancel protection, gesture gating")
    }
}
