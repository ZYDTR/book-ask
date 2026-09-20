import Foundation

/// Mouse events and polling observe the same physical button transition. Cache
/// the event's button state before handing out a revision, so the following poll
/// cannot invalidate a just-completed drag by counting its release a second time.
struct SelectionInteraction {
    private(set) var revision = 0
    private(set) var pressedButtons = 0

    mutating func event(buttons: Int) {
        revision += 1
        pressedButtons = buttons
    }

    @discardableResult
    mutating func observe(buttons: Int) -> Bool {
        guard buttons != pressedButtons else { return false }
        pressedButtons = buttons
        revision += 1
        return true
    }
}

/// A new, stable Books selection is the signal. App activation is not a reliable
/// gate: an auxiliary window or an accessibility interaction may retain focus.
struct SelectionTrigger {
    private var source: Int32?
    private var accepted = ""
    private var pending = ""
    private var pendingSince: TimeInterval = 0
    private(set) var decision = "initial"
    var evidence: [String: Any] { ["decision": decision, "pending": pending, "accepted": accepted, "pendingSince": pendingSince] }

    mutating func interrupt(_ reason: String) { pending = ""; decision = reason }

    mutating func sample(_ text: String, source: Int32, frontmost: Bool,
                         mouseDown: Bool, complete: Bool, now: TimeInterval) -> String? {
        guard !mouseDown else { interrupt("mouse_down"); return nil }
        guard complete || !text.isEmpty else { interrupt("incomplete_read"); return nil }
        if self.source != source {
            self.source = source
            pending = ""
            // Do not open an old selection when starting while another app is active.
            accepted = frontmost ? "" : text
            if !frontmost { decision = "startup_baseline"; return nil }
        }
        guard !text.isEmpty, text.count <= 6000, text != accepted else {
            pending = ""
            decision = text.isEmpty ? "empty" : (text.count > 6000 ? "too_long" : "already_accepted")
            return nil
        }
        if pending != text {
            pending = text
            pendingSince = now
            decision = "candidate_changed"
            return nil
        }
        guard now - pendingSince >= 0.4 else { decision = "settling"; return nil }
        accepted = text
        pending = ""
        decision = "accepted"
        return text
    }
}
