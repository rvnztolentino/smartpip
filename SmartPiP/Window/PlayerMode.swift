import Foundation

/// What the player is currently doing about the cursor.
///
/// One setting with three values, not two independent flags: the three are presented as
/// a single choice and exactly one is always ticked. Picking one selects it; picking the
/// one already selected does nothing, so there is no state where none is ticked and no
/// way to reach "avoiding while pinned in place", which was never coherent.
enum PlayerMode: String, CaseIterable {
    /// Neither mode. An ordinary always-on-top player: the only state with transport
    /// controls, and the only one you can drop a file onto or resize by hand.
    case plain

    /// The window moves out of the cursor's way.
    case avoid

    /// The window is click-through and stays put.
    case lock

    static let `default`: PlayerMode = .avoid

    /// Transport controls appear only when nothing is switched on. In either other
    /// mode the player is meant to be out of the way, and controls that fade in
    /// under the pointer are the opposite of that.
    var showsTransportControls: Bool { self == .plain }

    /// Locked, the window passes every mouse event straight through.
    var isClickThrough: Bool { self == .lock }

    /// Whether the window should run from an approaching cursor.
    var avoidsCursor: Bool { self == .avoid }

    /// Whether the global cursor poll needs to be running.
    ///
    /// Avoid needs it to measure how close the pointer is. Lock needs it to fade the
    /// window while the pointer rests over it — a click-through window gets no mouse
    /// events of its own, so an `NSTrackingArea` would never fire. A plain player
    /// wants neither, and the timer stops.
    var needsCursorTracking: Bool { self != .plain }

    /// Whether a file can be dropped on the window and an edge dragged to resize it.
    ///
    /// Both are direct manipulation of a window that the other two modes exist to keep
    /// out of your way, so both are refused there. Avoid would run from the drag; Lock
    /// would hand it to whatever is underneath. Refusing outright is more honest than
    /// letting it work only if you are quick enough.
    var acceptsDirectManipulation: Bool { self == .plain }

    /// Title of this mode's menu item, in both menus.
    var menuTitle: String {
        switch self {
        case .plain: "Normal Player"
        case .avoid: "Avoid Cursor"
        case .lock: "Lock Player"
        }
    }

    /// What to tell someone who tries to drop a file or resize the window, and `nil`
    /// when there is nothing to say because both already work.
    ///
    /// Kept to two short lines. It is shown inside a small player, sometimes over a video,
    /// so anything longer is read as clutter and skipped.
    var directManipulationAdvice: String? {
        switch self {
        case .plain: nil
        case .avoid:
            """
            Avoid mode is on.
            \(Self.escapeAdvice)
            """
        case .lock:
            """
            Lock mode is on.
            \(Self.escapeAdvice)
            """
        }
    }

    /// Named once: both modes are left the same way, and the wording should not drift.
    private static let escapeAdvice = "Pick Normal Player to drop a file or resize, or use Open."

    /// SF Symbol shown in the menu bar.
    var statusSymbolName: String {
        switch self {
        case .plain: "play.rectangle"
        case .avoid: "pip"
        case .lock: "lock.fill"
        }
    }

    var statusDescription: String {
        switch self {
        case .plain: "SmartPiP: normal player"
        case .avoid: "SmartPiP: avoiding the cursor"
        case .lock: "SmartPiP: locked, clicks pass through"
        }
    }
}
