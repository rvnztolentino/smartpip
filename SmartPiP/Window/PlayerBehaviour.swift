import Foundation

/// What the player is doing right now: its mode, and whether the override key is held.
///
/// Ask this rather than `PlayerMode`. The mode describes what the player does when nothing
/// is held, which is only half the answer: holding the override key hands every mode back
/// the things it gave up, so "can this be resized" and "do clicks land on it" depend on
/// both. Keeping the two facts in one value means no call site can consult the mode and
/// forget the key.
struct PlayerBehaviour: Equatable {
    let mode: PlayerMode

    /// True while the override key is down. Not persisted and not a setting: it is only
    /// ever the answer to what is being held at this instant.
    let isOverridden: Bool

    init(mode: PlayerMode, isOverridden: Bool = false) {
        self.mode = mode
        self.isOverridden = isOverridden
    }

    /// Transport controls, which otherwise appear only in Normal Player.
    var showsTransportControls: Bool { isOverridden || mode.showsTransportControls }

    /// Clicks pass through a locked player, but never while the key is held: taking the
    /// clicks back is most of what full control means.
    var isClickThrough: Bool { !isOverridden && mode.isClickThrough }

    /// Whether the window should run from an approaching cursor.
    ///
    /// Off while the key is held, along with `peeksFromCursor`: these are the two things the
    /// player does that move the window by itself, and nothing should move under a hand that
    /// is reaching for it.
    var avoidsCursor: Bool { !isOverridden && mode.avoidsCursor }

    /// Whether the cursor arriving should tuck the window against the screen edge.
    ///
    /// Off while the key is held, which also brings a player that is already tucked away
    /// back out: a hidden window you have just taken control of is of no use to anyone.
    var peeksFromCursor: Bool { !isOverridden && mode.peeksFromCursor }

    /// Whether a file can be dropped on the window, and an edge dragged to move or resize it.
    var acceptsDirectManipulation: Bool { isOverridden || mode.acceptsDirectManipulation }

    /// Whether *you* can collapse the player to the screen edge.
    ///
    /// The one thing the hold does not lend out, and the reason is on `PlayerMode.canCollapse`:
    /// it settles where the window sits, which is the very thing the other three modes are
    /// about. Borrowing it for as long as a key is held would leave a player collapsed in a
    /// mode that has its own ideas about where the window belongs.
    var canCollapse: Bool { mode.canCollapse }

    /// Whether the global cursor poll needs to be running.
    ///
    /// Deliberately not overridable. The poll is the only thing that notices the key coming
    /// back up, so switching it off while the key is held would leave the player overridden
    /// for good.
    var needsCursorTracking: Bool { mode.needsCursorTracking }

    /// What to tell someone who tries to drop a file or resize, and `nil` when there is
    /// nothing to say because both already work.
    var directManipulationAdvice: String? {
        isOverridden ? nil : mode.directManipulationAdvice
    }
}
