import AppKit

/// Decides where a collapsed player rests, and which side it tucks itself against.
///
/// Pure geometry, like `AvoidanceResolver`: rectangles in, a rectangle or a side out, with
/// no window and no state, so the whole rule can be exercised without anything on screen.
enum CollapseResolver {
    /// The side of the screen a window collapses against.
    enum Side {
        case left
        case right
    }

    /// Which side `frame` slides off.
    ///
    /// The window is always parked in a corner, which puts it the same distance from a side
    /// edge as from the top or bottom one, so "nearest" has to be settled rather than
    /// measured. It goes off the side it is already on, and never off the top or the bottom:
    /// a tab along a horizontal edge would be a wide flat sliver competing with the menu bar
    /// or the Dock, where one down the side is the shape everything else on macOS uses to
    /// tuck itself away at an edge.
    static func side(for frame: NSRect, in visibleFrame: NSRect) -> Side {
        frame.midX < visibleFrame.midX ? .left : .right
    }

    /// Where `frame` rests when collapsed, with `tab` points of it left inside `visibleFrame`.
    ///
    /// What stays in view is exactly the width of the tab, and the tab sits on the window's
    /// inner edge, so collapsing leaves the tab flush against the screen edge and nothing
    /// else. That is the whole trick: there is no separate control to place or hide, only
    /// the one already on the window arriving at the edge.
    ///
    /// Measured against `visibleFrame` rather than the whole screen, like every other
    /// placement in the app, so it comes to rest against the edge of the area the window is
    /// allowed to use instead of underneath a Dock parked on that side.
    ///
    /// Only the horizontal position changes. How far up the screen the window sits is the
    /// corner's business, and a slide that also drifted vertically would look like the
    /// window had been put somewhere else rather than tucked aside.
    static func restingFrame(for frame: NSRect, in visibleFrame: NSRect, tab: CGFloat) -> NSRect {
        // Never wider than the window itself, and never negative: a tab out of either bound
        // would leave the window somewhere neither collapsed nor in view.
        let tab = min(max(tab, 0), frame.width)

        var resting = frame
        switch side(for: frame, in: visibleFrame) {
        case .left:
            resting.origin.x = visibleFrame.minX + tab - frame.width
        case .right:
            resting.origin.x = visibleFrame.maxX - tab
        }
        return resting
    }

    /// Everywhere a peeking player counts as being, whether it is out or tucked away.
    ///
    /// Where it stands and where it rests, together, plus everything between them and
    /// `margin` around the lot. Peek uses this to decide when to come back, and it has to be
    /// the whole region rather than just the window, or the mode oscillates: the cursor that
    /// tucked the player away is left sitting exactly where the player used to be, so it
    /// reads as clear the instant the window leaves, comes back, is arrived at again, and
    /// goes. That runs about once a second with the pointer perfectly still.
    ///
    /// Measured from `standing` rather than from wherever the window is at this moment, so
    /// the answer does not change underneath the rule that is asking it.
    static func occupiedArea(
        standing: NSRect, in visibleFrame: NSRect, tab: CGFloat, margin: CGFloat
    ) -> NSRect {
        let resting = restingFrame(for: standing, in: visibleFrame, tab: tab)
        return standing
            .union(resting.intersection(visibleFrame))
            .insetBy(dx: -margin, dy: -margin)
    }
}
