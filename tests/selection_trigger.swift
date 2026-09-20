import Foundation

@main struct SelectionTriggerTests {
    static func main() {
        // Reproduces the candidate's mouse-up -> scheduled revision -> immediate
        // AX poll sequence. The old event handler advanced the revision but left
        // the polled mouse-down state cached, so every sampled drag self-cancelled.
        let oldReleaseCache = CommandLine.arguments.contains("--old-release-cache")
        var interaction = SelectionInteraction()
        interaction.event(buttons: 1)
        interaction.observe(buttons: 1)
        interaction.event(buttons: oldReleaseCache ? 1 : 0)
        let scheduledRevision = interaction.revision
        interaction.observe(buttons: 0)
        if scheduledRevision != interaction.revision {
            fputs("FAIL: completed drag must survive the immediate release poll\n", stderr)
            exit(1)
        }
        interaction.event(buttons: 1)
        if scheduledRevision == interaction.revision {
            fputs("FAIL: a genuinely new gesture must invalidate the old capture\n", stderr)
            exit(1)
        }
        var trigger = SelectionTrigger()
        let oldGate = CommandLine.arguments.contains("--old-foreground-gate")
        func read(_ text: String, _ time: Double, front: Bool = false,
                  down: Bool = false, source: Int32 = 10, complete: Bool = true) -> String? {
            // Counterfactual: the previous implementation discarded these actual
            // Books samples solely because the frontmost-app query was false.
            if oldGate && !front { return nil }
            return trigger.sample(text, source: source, frontmost: front,
                                  mouseDown: down, complete: complete, now: time)
        }
        func check(_ value: Bool, _ name: String) {
            if !value { fputs("FAIL: \(name)\n", stderr); exit(1) }
        }
        check(read("old selection", 0) == nil, "ignore selection left over at startup")
        check(read("old selection", 1) == nil, "no startup API request")
        check(read("bulldozer", 2) == nil, "wait for selection to settle")
        check(read("bulldozer", 2.2) == nil, "short-lived selection cannot trigger")
        check(read("bulldozer", 2.5) == "bulldozer", "new Books selection must trigger even when focus remains elsewhere")
        check(read("", 3) == nil, "empty accessibility read is harmless")
        check(read("bulldozer", 4, front: true) == nil, "returning to Books cannot reopen same selection")
        check(read("fragile", 5, down: true) == nil, "never interrupt mouse dragging")
        check(read("fragile", 6) == nil, "first sample after mouse release")
        check(read("fragile", 6.5) == "fragile", "accept settled selection after release")
        check(read("old selection", 7, source: 11) == nil, "restarting Books reestablishes baseline")
        check(read("", 8, source: 12, complete: false) == nil, "incomplete traversal cannot establish baseline")
        check(read("old selection", 9, source: 12) == nil, "later complete read is still startup baseline")
        check(read("new fragment", 10, source: 12) == nil, "start a candidate")
        trigger.interrupt("mouse_down")
        check(read("new fragment", 11, source: 12) == nil, "a new gesture cannot inherit an earlier settling interval")
        check(trigger.decision == "candidate_changed", "diagnostics explain why a candidate was held")
        check(read("new fragment", 11.5, source: 12) == "new fragment", "gesture must settle again")
        check(trigger.decision == "accepted", "diagnostics expose acceptance")
        print("PASS: selection trigger regression")
    }
}
