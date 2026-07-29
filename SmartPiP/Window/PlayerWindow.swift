import AppKit

/// Borderless, always-on-top window that holds the player.
///
/// It is deliberately not user-movable: position is owned entirely by
/// `PlayerWindowController`, which only ever parks it in a screen corner.
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
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .black
        minSize = Layout.minimumContentSize
        preventsApplicationTerminationWhenModal = false
    }
}
