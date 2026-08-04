import AppKit

/// Moves the player window for the length of one press, without handing the drag to the
/// system.
///
/// `NSWindow.performDrag(with:)` and `isMovableByWindowBackground` both route a drag through
/// the window server's own drag loop. That loop offers to tile the window whenever it nears
/// a screen edge: a translucent outline appears and letting go there resizes the player to
/// half the display. There is no supported way to decline that while still using the system
/// drag, and a player whose only legal positions are four corners must never be tiled, so
/// the frame is moved by hand instead.
///
/// Doing it by hand also means the release arrives as an ordinary `mouseUp`. The system drag
/// runs a modal loop that swallows the release, which is why parking the window used to need
/// a timer polling the button state.
@MainActor
final class WindowDragger {
    /// Distance from the window's origin to the cursor when the press landed, in screen
    /// coordinates. Nil whenever no drag is in progress.
    private var grabOffset: NSSize?
    private var hasMoved = false

    /// Takes hold of the window. Returns false when there is nothing to take hold of, so the
    /// caller can let the press be handled normally.
    @discardableResult
    func begin(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        let cursor = NSEvent.mouseLocation
        grabOffset = NSSize(
            width: cursor.x - window.frame.minX,
            height: cursor.y - window.frame.minY)
        hasMoved = false
        return true
    }

    /// Follows the cursor.
    ///
    /// Measured against `NSEvent.mouseLocation` rather than the event's own location. The
    /// event is reported in the view's coordinates, and the view is moving, so its idea of
    /// where the pointer is changes as the window catches up with it.
    func drag(in window: NSWindow?) {
        guard let grabOffset, let window else { return }
        hasMoved = true
        let cursor = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(x: cursor.x - grabOffset.width, y: cursor.y - grabOffset.height))
    }

    /// Lets go, and reports whether the window actually went anywhere.
    ///
    /// A press that never moved returns false, so clicking the picture to bring the player
    /// forward does not also re-park it in a corner.
    @discardableResult
    func end() -> Bool {
        let moved = grabOffset != nil && hasMoved
        grabOffset = nil
        hasMoved = false
        return moved
    }
}
