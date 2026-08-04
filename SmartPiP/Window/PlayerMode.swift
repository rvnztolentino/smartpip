import Foundation

/// What the player is currently doing about the cursor.
///
/// One setting with four values, not a set of independent flags: the four are presented as
/// a single choice and exactly one is always ticked. Picking one selects it; picking the
/// one already selected does nothing, so there is no state where none is ticked and no way
/// to reach a combination like "avoiding while pinned in place", which was never coherent.
///
/// Normal is the default and comes first, because it is the state the other three are
/// departures from, and because a player that starts by doing nothing on its own is the
/// one that needs the least explaining.
///
/// What the mode says here is what the player does when nothing is held. Holding the
/// override key gives every mode back what it gave up, so anything asking what the player
/// will actually allow should ask `PlayerBehaviour` instead.
///
/// `allCases` is the order both menus present, so a mode added here appears in both without
/// anything else being touched.
enum PlayerMode: String, CaseIterable {
    /// No mode at all. An ordinary always-on-top player: the one state with transport
    /// controls, and the one you can drop a file onto, resize by hand, or collapse yourself.
    case plain

    /// The window is click-through and stays put.
    case lock

    /// The window slides off the nearest side edge when the cursor arrives, and comes back
    /// once it has gone.
    case peek

    /// The window moves out of the cursor's way.
    case avoid

    static let `default`: PlayerMode = .plain

    /// Transport controls appear only when nothing is switched on. In the other three modes
    /// the player is meant to be out of the way, and controls that fade in under the pointer
    /// are the opposite of that.
    var showsTransportControls: Bool { self == .plain }

    /// Locked, the window passes every mouse event straight through.
    var isClickThrough: Bool { self == .lock }

    /// Whether the window should run from an approaching cursor.
    var avoidsCursor: Bool { self == .avoid }

    /// Whether the cursor arriving at the window should tuck it against the screen edge, and
    /// the cursor leaving should bring it back.
    ///
    /// The other half of `avoidsCursor`: both get out of the way of the pointer, and the
    /// difference is only where they go. Avoid takes the whole window to another corner and
    /// stays there; Peek slides it aside and comes back once you have gone.
    var peeksFromCursor: Bool { self == .peek }

    /// Whether the global cursor poll needs to be running.
    ///
    /// Avoid needs it to measure how close the pointer is, and Peek to know when it has
    /// arrived and gone. Lock needs it to fade the window while the pointer rests over it —
    /// a click-through window gets no mouse events of its own, so an `NSTrackingArea` would
    /// never fire. All three also need it to notice the override key. A plain player wants
    /// none of that, and the timer stops.
    var needsCursorTracking: Bool { self != .plain }

    /// Whether a file can be dropped on the window and an edge dragged to resize it.
    ///
    /// Both are direct manipulation of a window that the other three modes exist to keep out
    /// of your way, so none of them offers it by default. Avoid would run from the drag, Lock
    /// would hand it to whatever is underneath, and Peek would slide out from under it.
    /// Refusing outright is more honest than letting it work only if you are quick enough,
    /// and the override key is there for when you mean it.
    var acceptsDirectManipulation: Bool { self == .plain }

    /// Whether *you* can collapse the player to the screen edge, from the menus or from the
    /// controls on the window.
    ///
    /// Normal Player only, and unlike everything above it, the override key does not lend it
    /// out. Peek arrives at the same place by itself, which is the point of the mode, but it
    /// is the cursor doing it rather than you. Avoid and Lock have their own ideas about
    /// where the window belongs, and a player that could be tucked away while avoiding would
    /// have two answers and spend its time arguing with itself.
    var canCollapse: Bool { self == .plain }

    /// Title of this mode's menu item, in both menus.
    var menuTitle: String {
        switch self {
        case .plain: "Normal Player"
        case .lock: "Lock Player"
        case .peek: "Peek Player"
        case .avoid: "Avoid Cursor"
        }
    }

    /// What to tell someone who tries to drop a file or resize the window, and `nil` when
    /// there is nothing to say because both already work.
    ///
    /// Kept to two short lines. It is shown inside a small player, sometimes over a video,
    /// so anything longer is read as clutter and skipped.
    var directManipulationAdvice: String? {
        switch self {
        case .plain: nil
        case .lock:
            """
            Lock mode is on.
            \(Self.escapeAdvice)
            """
        case .peek:
            """
            Peek mode is on.
            \(Self.escapeAdvice)
            """
        case .avoid:
            """
            Avoid mode is on.
            \(Self.escapeAdvice)
            """
        }
    }

    /// Named once: all three modes are left the same way, and the wording should not drift.
    ///
    /// It names the hold rather than the Normal Player menu item because the hold is the
    /// shorter answer and it works where you already are, without giving up the mode you
    /// chose. Both menus still carry Normal Player for anyone who wants it for good.
    private static let escapeAdvice = "Hold \(OverrideKey.displayName) to drop a file or resize."

    /// SF Symbol shown in the menu bar.
    var statusSymbolName: String {
        switch self {
        case .plain: "play.rectangle"
        case .lock: "lock.fill"
        case .peek: "sidebar.right"
        case .avoid: "pip"
        }
    }

    var statusDescription: String {
        switch self {
        case .plain: "SmartPiP: normal player"
        case .lock: "SmartPiP: locked, clicks pass through"
        case .peek: "SmartPiP: peeking from the edge"
        case .avoid: "SmartPiP: avoiding the cursor"
        }
    }
}
