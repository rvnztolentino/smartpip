import Foundation

/// Sizing and placement constants for the floating player window.
enum Layout {
    /// Gap between the window and the edges of `NSScreen.visibleFrame`.
    static let cornerMargin: CGFloat = 16

    /// Size used before any file has been opened, and the fallback when a file
    /// reports no usable video dimensions.
    static let defaultContentSize = NSSize(width: 480, height: 270)

    /// Longest edge the window is allowed to take when it resizes itself to a
    /// newly opened video. Keeps the player small enough to stay out of the way.
    static let preferredLongestEdge: CGFloat = 480

    /// Smallest the window may become, so it never collapses out of reach.
    static let minimumContentSize = NSSize(width: 192, height: 108)

    /// Duration of an animated corner move.
    static let cornerAnimationDuration: TimeInterval = 0.25
}
