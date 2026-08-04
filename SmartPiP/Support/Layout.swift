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

    /// Width of the collapse tab, which is also exactly how much of a collapsed player is
    /// left in view: the tab sits on the window's inner edge, so collapsing brings it flush
    /// against the screen edge and leaves nothing else behind.
    ///
    /// Wide enough to click without aiming, because the pointer stops dead at the screen
    /// edge and lands on the tab whatever speed it arrives at. Narrow enough that what is
    /// left reads as an edge marker rather than as a window someone forgot to close.
    static let collapseTabWidth: CGFloat = 16

    /// Height of the collapse tab. Tall enough to be an easy target and to read as a handle,
    /// short enough to stay clear of the transport controls at the smallest window size.
    static let collapseTabHeight: CGFloat = 48

    /// Size of the square collapse button in the corner of a standing normal player. Small
    /// enough to sit over a picture without competing with it, big enough to hit.
    static let collapseIconSize: CGFloat = 22

    /// Gap between that button and the corner of the player.
    static let collapseIconInset: CGFloat = 8

    /// How long the cursor has to stay clear of a peeking player before it comes back.
    ///
    /// There is no matching delay for getting out of the way, which happens at once: the
    /// cursor arriving is the whole signal, and a player that waited would be in the way for
    /// exactly as long as the wait. Coming back is the direction that needs any patience at
    /// all, so leaving the corner for a moment on the way past does not make the window
    /// spring out.
    ///
    /// Short. It only has to outlast a pointer passing through, which takes a fraction of
    /// this, and every extra tenth is time spent looking at an empty corner waiting for the
    /// video to come back. Still several samples of the poll, so it cannot fire on one
    /// stray reading.
    static let peekReturnDelay: TimeInterval = 0.2
}
