import AppKit

/// Decides where the player runs to when the cursor closes in on it.
///
/// Pure geometry: rectangles and points in, a corner out. No window, no state, no
/// timers — so the whole rule can be exercised without anything on screen, which is
/// the only practical way to test a behaviour that is otherwise a pointer chase.
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
    /// Always the next corner clockwise — the same rotation the Cycle Corner
    /// shortcut uses, so the player only ever travels one way and you can see
    /// where it is going before it goes there.
    ///
    /// The single exception is a corner the cursor is already near: it keeps going
    /// clockwise until it finds one that is clear. Direction never changes, only
    /// how far around it steps.
    ///
    /// "Clear" means the release distance rather than the trigger distance. Landing
    /// inside that gap would leave the window somewhere it is too close to re-arm
    /// but too far to run, so it would sit there ignoring the cursor.
    static func destination(
        from corner: ScreenCorner,
        size: NSSize,
        cursor: NSPoint,
        visibleFrame: NSRect,
        margin: CGFloat
    ) -> ScreenCorner {
        var candidate = corner.next

        // At most the other three corners; if the cursor somehow covers all of
        // them the plain clockwise step is still the answer.
        for _ in 1..<ScreenCorner.allCases.count {
            let frame = candidate.frame(for: size, in: visibleFrame, margin: margin)
            if distance(from: cursor, to: frame) >= Layout.avoidReleaseDistance {
                return candidate
            }
            candidate = candidate.next
        }

        return corner.next
    }
}
