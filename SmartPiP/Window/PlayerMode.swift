import Foundation

/// What the player is currently doing about the cursor.
///
/// Avoid and Lock are mutually exclusive — switching one on switches the other off —
/// so this is one setting with three values rather than two independent flags. At most
/// one mode is ever ticked in the menus, and "avoiding while pinned in place", which
/// was never coherent, is not representable.
enum PlayerMode: String, CaseIterable {
    /// Neither mode. An ordinary always-on-top player, and the only state that has
    /// transport controls.
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

    /// The mode you land in after asking for `mode`.
    ///
    /// Asking for the mode you are already in switches it off; asking for the other
    /// one replaces it. That is what makes the two menu items behave like one choice.
    func toggled(_ mode: PlayerMode) -> PlayerMode {
        self == mode ? .plain : mode
    }

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
        case .plain: "SmartPiP — plain player"
        case .avoid: "SmartPiP — avoiding the cursor"
        case .lock: "SmartPiP — locked, clicks pass through"
        }
    }
}
