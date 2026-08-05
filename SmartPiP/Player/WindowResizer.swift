import AppKit

/// Resizes the player window for the length of one press, without handing the resize to the
/// system.
///
/// By hand for the same reason `WindowDragger` moves it by hand, and a second one. AppKit's
/// own resize loop is reached by putting `.resizable` in the style mask, and on a window with
/// no chrome it gives you only the few points it reserves at each corner: the sides of the
/// player were not grabbable at all. Doing it here makes every edge a handle, and keeps the
/// window's size in the same hands as its position.
///
/// The aspect lock is ours too, for the same reason. `contentAspectRatio` constrains AppKit's
/// resize and nothing else, so a hand-rolled one that ignored it would let the video out of
/// its own shape; `ResizeResolver` holds the ratio instead.
@MainActor
final class WindowResizer {
    /// The frame when the press landed, and where the cursor was. Both nil whenever no
    /// resize is in progress, and both fixed for the length of one: every frame is measured
    /// from the start rather than from the frame before it.
    private var startFrame: NSRect?
    private var startCursor: NSPoint = .zero

    private var edges: ResizeEdge = []
    private var limits: ResizeLimits?
    private var hasResized = false

    /// Takes hold of an edge. Returns false when there is nothing to take hold of, so the
    /// caller can let the press be a move or a click instead.
    @discardableResult
    func begin(in window: NSWindow?, edges: ResizeEdge, limits: ResizeLimits) -> Bool {
        guard let window, !edges.isEmpty else { return false }
        startFrame = window.frame
        startCursor = NSEvent.mouseLocation
        self.edges = edges
        self.limits = limits
        hasResized = false
        return true
    }

    /// Follows the cursor.
    ///
    /// Measured against `NSEvent.mouseLocation` rather than the event's own location, exactly
    /// as the drag is: the event arrives in the view's coordinates and the view is being
    /// resized, so its idea of where the pointer is moves with the edge you are holding.
    func drag(in window: NSWindow?) {
        guard let window, let startFrame, let limits else { return }

        let cursor = NSEvent.mouseLocation
        let frame = ResizeResolver.frame(
            from: startFrame,
            edges: edges,
            translation: NSSize(
                width: cursor.x - startCursor.x,
                height: cursor.y - startCursor.y),
            limits: limits)

        guard frame != window.frame else { return }
        hasResized = true
        window.setFrame(frame, display: true)
    }

    /// Lets go, and reports whether the window actually changed size.
    ///
    /// A press that never moved returns false, so a click on the edge of the picture does not
    /// also re-park the player.
    @discardableResult
    func end() -> Bool {
        let resized = startFrame != nil && hasResized
        startFrame = nil
        limits = nil
        edges = []
        hasResized = false
        return resized
    }
}
