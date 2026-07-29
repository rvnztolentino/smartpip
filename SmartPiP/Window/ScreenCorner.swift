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

    /// The next corner clockwise.
    var next: ScreenCorner {
        let all = ScreenCorner.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
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
