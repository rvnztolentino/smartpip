import AppKit

/// The only positions the player window is allowed to occupy.
///
/// `allCases` is ordered clockwise starting from the top-left, which is also the
/// order `next` cycles through.
enum ScreenCorner: String, CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    /// Where the player opens before it has ever been moved. Bottom-right is the
    /// emptiest corner on a stock desktop — furthest from the menu bar, and clear of a
    /// Dock parked at the bottom by `visibleFrame`.
    static let `default`: ScreenCorner = .bottomRight

    /// The next corner clockwise.
    ///
    /// The rotation behind the Cycle Corner shortcut, which is the one place in the app
    /// that walks all four corners in order. Avoid used to step through this as well and
    /// no longer does: see `verticalCounterpart`.
    var next: ScreenCorner {
        let all = ScreenCorner.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// The corner directly above or below this one, on the same side of the screen.
    ///
    /// Where an avoiding player goes. The dodge is vertical only, so the window swaps top
    /// for bottom and stays on the side you left it on: a player on the right stays on the
    /// right, and one on the left stays on the left.
    ///
    /// Moving on one axis rather than around all four corners means the window ends up
    /// somewhere you can predict from where it started, and it never crosses the middle of
    /// the screen, which is where the thing you are actually looking at usually is.
    var verticalCounterpart: ScreenCorner {
        switch self {
        case .topLeft: .bottomLeft
        case .bottomLeft: .topLeft
        case .topRight: .bottomRight
        case .bottomRight: .topRight
        }
    }

    /// The corner for a window dragged so that its centre sits at `point`.
    ///
    /// Quadrants of `visibleFrame`, rather than distance to each corner's anchor: which
    /// half of the screen you dragged towards is something you can judge by eye while
    /// dragging, so the window lands where you meant it to. Ties go to the corner that
    /// `frame(for:in:margin:)` measures from, which is bottom-left.
    static func nearest(to point: NSPoint, in visibleFrame: NSRect) -> ScreenCorner {
        switch (point.x >= visibleFrame.midX, point.y >= visibleFrame.midY) {
        case (false, true): .topLeft
        case (true, true): .topRight
        case (true, false): .bottomRight
        case (false, false): .bottomLeft
        }
    }

    /// Frame for a window of `size` parked in this corner of `visibleFrame`.
    ///
    /// `visibleFrame` is expected to be `NSScreen.visibleFrame`, so the result
    /// already respects the menu bar and the Dock. The size is clamped to the
    /// available area first, so an oversized window is shrunk rather than pushed
    /// off screen.
    func frame(for size: NSSize, in visibleFrame: NSRect, margin: CGFloat) -> NSRect {
        let available = NSSize(
            width: max(visibleFrame.width - margin * 2, 0),
            height: max(visibleFrame.height - margin * 2, 0)
        )
        let clamped = NSSize(
            width: min(size.width, available.width),
            height: min(size.height, available.height)
        )

        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - margin - clamped.width
        let minY = visibleFrame.minY + margin
        let maxY = visibleFrame.maxY - margin - clamped.height

        // AppKit screen coordinates are bottom-left origin, so "top" is maxY.
        let origin: NSPoint
        switch self {
        case .topLeft:
            origin = NSPoint(x: minX, y: maxY)
        case .topRight:
            origin = NSPoint(x: maxX, y: maxY)
        case .bottomRight:
            origin = NSPoint(x: maxX, y: minY)
        case .bottomLeft:
            origin = NSPoint(x: minX, y: minY)
        }

        return NSRect(origin: origin, size: clamped)
    }
}
