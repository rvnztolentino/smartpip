import Foundation

/// The behaviours currently switched on.
///
/// Avoid and Lock are independent toggles rather than two halves of one setting, so
/// "neither" is a real state: an ordinary always-on-top player that behaves like any
/// other window. That state is the only one with transport controls.
struct PlayerModes: OptionSet {
    let rawValue: Int

    /// The window gets out of the cursor's way.
    static let avoid = PlayerModes(rawValue: 1 << 0)

    /// The window is click-through and stays put.
    static let lock = PlayerModes(rawValue: 1 << 1)

    /// Default: dodging, but still interactive.
    static let `default`: PlayerModes = [.avoid]

    /// Transport controls appear only when nothing is switched on. With either mode
    /// active the player is meant to be out of the way, and controls that fade in
    /// under the pointer are the opposite of that.
    var showsTransportControls: Bool { isEmpty }

    /// Locked, the window passes every mouse event straight through.
    var isClickThrough: Bool { contains(.lock) }

    /// Whether the global cursor poll needs to be running.
    ///
    /// Only Lock needs it today, to fade the window while the pointer rests over it —
    /// a click-through window gets no mouse events of its own. Avoid will need it too
    /// once the dodge lands.
    var needsCursorTracking: Bool { contains(.lock) }

    /// SF Symbol shown in the menu bar.
    var statusSymbolName: String {
        if contains(.lock) { return "lock.fill" }
        if contains(.avoid) { return "pip" }
        return "play.rectangle"
    }

    var statusDescription: String {
        switch (contains(.avoid), contains(.lock)) {
        case (_, true): "SmartPiP — locked, clicks pass through"
        case (true, false): "SmartPiP — avoiding the cursor"
        case (false, false): "SmartPiP — plain player"
        }
    }
}
