import Foundation

/// Decides *whether* a peeking player should be tucked away, where `CollapseResolver`
/// decides where it goes.
///
/// A state machine over a stream of "is the cursor at the player" samples, split out for the
/// same reason as `AvoidanceTrigger`: fed a sequence of samples and times it can be checked
/// outright, which is the only honest way to test a rule whose substance is how long
/// something has been true.
struct PeekTrigger {
    /// True while the window rests off the edge.
    private(set) var isHidden = false

    /// When the cursor first got clear. Nil whenever it is not, so a wait that is part served
    /// is abandoned rather than banked.
    private var clearSince: Date?

    /// Whether the window should be tucked away now.
    ///
    /// Getting out of the way is immediate, like Avoid: the cursor arriving is the whole
    /// signal, and a player that waited would be in the way for exactly as long as the wait.
    /// Coming back waits, because leaving the player's corner for a moment on the way past is
    /// not the same as being finished with it, and a window that sprang out every time would
    /// be worse than one that never moved.
    ///
    /// `isCursorAtPlayer` has to be measured against everywhere the player would be, not just
    /// where it is now. See `CollapseResolver.occupiedArea`.
    mutating func update(isCursorAtPlayer: Bool, now: Date = Date()) -> Bool {
        guard !isCursorAtPlayer else {
            clearSince = nil
            isHidden = true
            return true
        }

        guard isHidden else { return false }

        let since = clearSince ?? now
        clearSince = since
        guard now.timeIntervalSince(since) >= Layout.peekReturnDelay else { return true }

        isHidden = false
        clearSince = nil
        return false
    }

    /// Call when the window is put somewhere by something other than this: the mode changing,
    /// or the override key taking over. A wait that was part served described a window that
    /// is no longer where it was.
    ///
    /// `hidden` is where the window has just been put, not a request to move it. Peek is
    /// switched on with the state read off the cursor's current position, so selecting the
    /// mode with the pointer already on the player tucks it away at once rather than showing
    /// it for a tick first.
    mutating func reset(hidden: Bool) {
        isHidden = hidden
        clearSince = nil
    }
}
