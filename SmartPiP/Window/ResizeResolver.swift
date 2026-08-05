import AppKit

/// The edges of the window a press has taken hold of.
///
/// One edge for a side, two for a corner, none for a press in the middle, which is a move
/// rather than a resize. A set rather than eight cases because that is what the arithmetic
/// wants: each edge contributes to the new frame on its own, and a corner is the two
/// contributions together.
struct ResizeEdge: OptionSet {
    let rawValue: Int

    static let left = ResizeEdge(rawValue: 1 << 0)
    static let right = ResizeEdge(rawValue: 1 << 1)
    static let bottom = ResizeEdge(rawValue: 1 << 2)
    static let top = ResizeEdge(rawValue: 1 << 3)

    var isHorizontal: Bool { !isDisjoint(with: [.left, .right]) }
    var isVertical: Bool { !isDisjoint(with: [.bottom, .top]) }
}

extension ResizeEdge {
    /// The pointer to show while hovering this band.
    ///
    /// The whole affordance. The window has no chrome and no visible border, so a resize
    /// that announced itself only by working would never be found: the pointer changing as
    /// you cross the edge is the only thing telling you the edge is there.
    ///
    /// `frameResize` is the pointer macOS itself shows on a window edge, and the only public
    /// way to get the diagonal ones. It arrived in macOS 15, so the two older pointers stand
    /// in below that: they name the wrong axis at a corner, and still say the one thing that
    /// matters, which is that this edge is a handle.
    var cursor: NSCursor {
        if #available(macOS 15.0, *), let position = framePosition {
            return .frameResize(position: position, directions: .all)
        }
        return isHorizontal ? .resizeLeftRight : .resizeUpDown
    }

    @available(macOS 15.0, *)
    private var framePosition: NSCursor.FrameResizePosition? {
        switch (contains(.top), contains(.bottom), contains(.left), contains(.right)) {
        case (true, _, true, _): .topLeft
        case (true, _, _, true): .topRight
        case (_, true, true, _): .bottomLeft
        case (_, true, _, true): .bottomRight
        case (true, _, _, _): .top
        case (_, true, _, _): .bottom
        case (_, _, true, _): .left
        case (_, _, _, true): .right
        default: nil
        }
    }
}

/// What a live resize has to stay inside.
///
/// Gathered at the moment of the press rather than read as it goes, so a resize is measured
/// against one set of rules from beginning to end even if the screen changes underneath it.
struct ResizeLimits {
    /// Smallest frame the shape may take, already grown into the player's own proportions.
    let minimum: NSSize

    /// Largest frame the screen leaves room for, margins included.
    let maximum: NSSize

    /// The corner the player is parked in, which is the edge that stays put on an axis the
    /// drag is not holding.
    let anchor: ScreenCorner
}

/// Where the edges of the window are, and where dragging one puts it.
///
/// Pure arithmetic on rectangles, with no window to hang it on, like `WindowSizing` and
/// `CollapseResolver` beside it. Resizing is the one gesture in the app that has to satisfy
/// four rules at once — the shape, the floor, the room on screen, and the corner the player
/// is parked in — so the rules are worked out here where they can be read together.
enum ResizeResolver {
    /// The edges a press at `point` takes hold of. `point` is in the window's own
    /// coordinates, so it is measured from the bottom left of the frame.
    ///
    /// The band is inside the window. A borderless window is sent nothing that lands beyond
    /// its own bounds, so a band drawn outside the frame would be one no press could ever
    /// reach.
    static func edges(at point: NSPoint, in size: NSSize, border: CGFloat) -> ResizeEdge {
        guard border > 0,
              (0...size.width).contains(point.x),
              (0...size.height).contains(point.y)
        else { return [] }

        // Never more than a third of the window. At the smallest size a fixed band would meet
        // itself in the middle, and every press anywhere on the player would be a resize with
        // nothing left to drag the window by.
        let horizontal = min(border, size.width / 3)
        let vertical = min(border, size.height / 3)

        var edges: ResizeEdge = []
        if point.x <= horizontal {
            edges.insert(.left)
        } else if point.x >= size.width - horizontal {
            edges.insert(.right)
        }
        if point.y <= vertical {
            edges.insert(.bottom)
        } else if point.y >= size.height - vertical {
            edges.insert(.top)
        }
        return edges
    }

    /// The frame a drag of `translation` from `start` asks for, once the shape, the limits
    /// and the parked corner have all had their say.
    ///
    /// `translation` is how far the cursor has travelled since the press, in screen points,
    /// so it is measured against where the drag began rather than against the last frame.
    /// Accumulating deltas instead would bank every rounding and every clamp: a drag that
    /// pushed past the floor and came back would return to a different size than it left.
    static func frame(
        from start: NSRect, edges: ResizeEdge, translation: NSSize, limits: ResizeLimits
    ) -> NSRect {
        guard !edges.isEmpty, start.width > 0, start.height > 0 else { return start }

        // The shape the window already has, rather than the video's own. They are the same
        // thing by the time a user can grab an edge — every size in the app comes from
        // `WindowSizing` — and taking it from the frame means the resize preserves exactly
        // what is on screen, including whatever rounding put it there.
        let ratio = start.height / start.width

        var width = start.width
        if edges.contains(.right) { width += translation.width }
        if edges.contains(.left) { width -= translation.width }

        var height = start.height
        if edges.contains(.top) { height += translation.height }
        if edges.contains(.bottom) { height -= translation.height }

        let size = clamped(
            width: lockedWidth(width: width, height: height, edges: edges, ratio: ratio),
            ratio: ratio,
            limits: limits)

        return NSRect(
            origin: origin(for: size, from: start, edges: edges, anchor: limits.anchor),
            size: size)
    }

    /// The width the aspect lock allows, given what the drag asked for on each axis.
    ///
    /// A side names one axis and the shape settles the other. A corner names both, and the
    /// shape only allows one, so the cursor is answered with the nearest size on the line the
    /// ratio draws. The obvious alternative, following whichever axis moved further, changes
    /// its mind every time the pointer crosses the diagonal, and the window jumps.
    private static func lockedWidth(
        width: CGFloat, height: CGFloat, edges: ResizeEdge, ratio: CGFloat
    ) -> CGFloat {
        switch (edges.isHorizontal, edges.isVertical) {
        case (true, false): width
        case (false, true): height / ratio
        default: (width + height * ratio) / (1 + ratio * ratio)
        }
    }

    /// `width` held between the floor and the ceiling, with the shape kept throughout.
    ///
    /// Both limits are brought onto the width before anything is compared, so the axis that
    /// runs out first stops the resize. Clamping each axis separately would let the window
    /// off its ratio at exactly the moment it is being asked to keep it.
    private static func clamped(width: CGFloat, ratio: CGFloat, limits: ResizeLimits) -> NSSize {
        let smallest = max(limits.minimum.width, limits.minimum.height / ratio)
        // The floor wins a screen too small to hold it. Nothing else can be honoured there,
        // and `PlayerWindowController` shrinks the window to fit when it parks it anyway.
        let largest = max(min(limits.maximum.width, limits.maximum.height / ratio), smallest)

        let locked = min(max(width, smallest), largest)
        // Whole points: a fractional frame lands the video on half a pixel and softens it.
        return NSSize(width: locked.rounded(), height: (locked * ratio).rounded())
    }

    /// Where the resized window sits, which is decided by whatever is *not* being dragged.
    ///
    /// The edge opposite the one in your hand stays where it is, so the window grows towards
    /// the cursor and nowhere else. On an axis the drag never named there is no opposite
    /// edge, and the parked corner stands in: keeping that corner still is what stops a
    /// player growing out of the corner it is meant to be sitting in and then snapping back
    /// when you let go.
    private static func origin(
        for size: NSSize, from start: NSRect, edges: ResizeEdge, anchor: ScreenCorner
    ) -> NSPoint {
        let (anchorsRight, anchorsTop) = switch anchor {
        case .topLeft: (false, true)
        case .topRight: (true, true)
        case .bottomRight: (true, false)
        case .bottomLeft: (false, false)
        }

        let holdsRight = edges.contains(.left) || (!edges.isHorizontal && anchorsRight)
        let holdsTop = edges.contains(.bottom) || (!edges.isVertical && anchorsTop)

        return NSPoint(
            x: holdsRight ? start.maxX - size.width : start.minX,
            y: holdsTop ? start.maxY - size.height : start.minY)
    }
}
