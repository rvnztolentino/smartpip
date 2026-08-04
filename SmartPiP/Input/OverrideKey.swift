import AppKit

/// The key you hold to take the player back, whatever mode it is in.
///
/// Every mode but Normal Player takes something away, and the whole point of holding this
/// is that you get all of it back for exactly as long as you hold it. Nothing is toggled
/// and nothing is remembered, so there is no state to get stuck in.
enum OverrideKey {
    /// Shown wherever the hold is explained. The word rather than the glyph: the advice is
    /// read in a small window, sometimes over a video, where ⌥ on its own is a guess.
    static let displayName = "Option"

    /// The modifiers an exact match is measured against.
    ///
    /// Caps Lock and Fn are left out deliberately. They are not part of what anyone means
    /// by holding Option, and treating either as a mismatch would make the override fail
    /// for no reason a user could see.
    private static let significant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// Whether the key is down right now, on its own.
    ///
    /// Exactly Option, not merely Option among others: every one of SmartPiP's own
    /// shortcuts contains it, so `contains(.option)` would flicker the override on each
    /// time you pressed one.
    ///
    /// Read on demand rather than watched with a global event monitor, for the same reason
    /// `CursorTracker` polls the pointer: a monitor needs the Input Monitoring permission,
    /// and this needs none.
    static var isHeld: Bool {
        NSEvent.modifierFlags.intersection(significant) == .option
    }
}
