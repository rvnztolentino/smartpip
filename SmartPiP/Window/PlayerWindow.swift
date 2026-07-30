import AppKit

/// Borderless, always-on-top window that holds the player.
///
/// Position is owned by `PlayerWindowController`, which only ever parks it in a screen
/// corner. A normal player can be dragged, but only to choose which corner: it snaps to
/// the quadrant you let go in. Whether dragging and resizing are allowed at all depends
/// on the mode, so the controller sets those too.
final class PlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        // `.borderless` is an empty option set; combining it with `.resizable`
        // yields a chrome-free window that can still be resized from its edges.
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .black
        preventsApplicationTerminationWhenModal = false

        // Size limits and the aspect lock are not set here: both depend on the shape of
        // whatever is playing, so `PlayerWindowController` owns them and updates them
        // together. Setting a floor here as well would just be a second answer to the
        // same question.
    }
}
