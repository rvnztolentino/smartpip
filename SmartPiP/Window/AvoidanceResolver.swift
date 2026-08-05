import AppKit

/// Decides where the player runs to when the cursor closes in on it.
///
/// Pure geometry: how far the cursor is from the window, and which corner the window
/// answers that with. No window, no state, no timers — so the whole rule can be exercised
/// without anything on screen, which is the only practical way to test a behaviour that is
/// otherwise a pointer chase.
enum AvoidanceResolver {

    /// Shortest distance from `point` to `rect`, and zero once the point is inside.
    ///
    /// Measured against the frame rather than the centre so the trigger distance
    /// means the same thing for a small window and a large one.
    static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// The corner the window should flee to.
    ///
    /// Straight up or straight down, on the side of the screen the player is already on.
    /// A player in a right-hand corner swaps between the two right-hand corners and a
    /// player on the left swaps between the two left-hand ones; it never changes sides.
    ///
    /// One destination rather than a choice, which is the whole difference from the
    /// clockwise rotation this replaced. That version walked on past any corner the cursor
    /// was already near, so it could always land somewhere clear. This one has nowhere else
    /// to go, so a cursor parked halfway up the screen can be left near the window after it
    /// has run. That is deliberate: `AvoidanceTrigger` holds the window still until the
    /// cursor is well clear, so it settles where it lands instead of flipping forever, and
    /// a predictable destination is worth more than a clear one.
    static func destination(from corner: ScreenCorner) -> ScreenCorner {
        corner.verticalCounterpart
    }
}
