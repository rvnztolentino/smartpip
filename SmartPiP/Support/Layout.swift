import Foundation

/// Sizing and placement constants for the floating player window.
enum Layout {
    /// Gap between the window and the edges of `NSScreen.visibleFrame`.
    static let cornerMargin: CGFloat = 16

    /// Size used before any file has been opened, and the fallback when a file
    /// reports no usable video dimensions.
    static let defaultContentSize = NSSize(width: 480, height: 270)

    /// Longest edge for a player that has never been resized — small enough to stay out
    /// of the way. Once the window has a size of its own, opening a file keeps that size
    /// instead of coming back to this one.
    static let preferredLongestEdge: CGFloat = 480

    /// Smallest the window may become, so it never collapses out of reach. Expressed as a
    /// 16:9 rectangle; `WindowSizing.minimumContentSize(for:)` reshapes it for videos of
    /// other proportions.
    static let minimumContentSize = NSSize(width: 192, height: 108)

    /// Duration of an animated corner move.
    static let cornerAnimationDuration: TimeInterval = 0.25

    /// Opacity while the cursor sits over a locked player, so you can read whatever is
    /// underneath without moving the window. Locking on its own does not dim.
    static let hoveredWindowAlpha: CGFloat = 0.3

    /// Extra margin the cursor must clear before a faded player comes back. Stops the
    /// fade flickering when the pointer rests on the window's edge.
    static let hoverHysteresis: CGFloat = 6

    /// Duration of the fade in and out.
    static let opacityFadeDuration: TimeInterval = 0.15

    /// How close the cursor has to get to the window's frame before the window runs.
    static let avoidTriggerDistance: CGFloat = 56

    /// How far the cursor must then get from the frame before the window will run
    /// again. The gap between this and the trigger distance is what stops a pointer
    /// parked near an edge from pumping the window around the screen.
    static let avoidReleaseDistance: CGFloat = 160
}
