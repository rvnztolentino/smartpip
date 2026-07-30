import Foundation

/// How big the player is and what shape it holds.
///
/// Pure arithmetic on sizes, with no window to hang it on, so the awkward cases — a
/// portrait video against a landscape floor, a remembered size from a plist someone has
/// edited — can be reasoned about and tested directly.
enum WindowSizing {
    /// `size` scaled so its longest edge measures `edge`, keeping its proportions.
    static func scaled(_ size: NSSize, toLongestEdge edge: CGFloat) -> NSSize {
        let longest = max(size.width, size.height)
        guard longest > 0, edge > 0 else { return size }
        return multiply(size, by: edge / longest)
    }

    /// The smallest content size allowed for something shaped like `aspect`.
    ///
    /// `Layout.minimumContentSize` is a single 16:9 rectangle, and using it verbatim as
    /// the floor for every video would mean a portrait window could shrink to 192 points
    /// wide and 108 tall — narrower than intended in one direction and the wrong shape in
    /// both. Growing the floor into the requested shape instead keeps a single number
    /// meaningful across aspects: whichever edge reaches its limit first stops the shrink.
    static func minimumContentSize(for aspect: NSSize) -> NSSize {
        let floor = Layout.minimumContentSize
        guard aspect.width > 0, aspect.height > 0 else { return floor }
        let scale = max(floor.width / aspect.width, floor.height / aspect.height)
        return multiply(aspect, by: scale)
    }

    /// Content size for a newly opened video.
    ///
    /// The new video takes the size the window already has rather than a fixed default,
    /// which is what makes a remembered size worth remembering: opening a file is the
    /// first thing you do after launch, so resetting to a default here would discard the
    /// restored size before it was ever seen. Only the shape changes; how big the player
    /// is stays the user's decision.
    static func contentSize(forVideo videoSize: NSSize?, currentLongestEdge: CGFloat) -> NSSize {
        guard let videoSize, videoSize.width > 0, videoSize.height > 0 else {
            return Layout.defaultContentSize
        }

        let edge = currentLongestEdge > 0 ? currentLongestEdge : Layout.preferredLongestEdge
        return shaped(like: videoSize, longestEdge: edge)
    }

    /// `aspect`'s shape at `edge`, never smaller than the floor for that shape.
    ///
    /// The floor is measured against `aspect` rather than against the scaled result.
    /// Deriving it from a size that has already been rounded to whole points compounds the
    /// rounding, and at small sizes the error is visible: a 1234x567 video asked to fit a
    /// 60 pt window came out 231x108, a different shape from the video, and a remembered
    /// 12x7 came back as 192x112 instead of 16:9.
    private static func shaped(like aspect: NSSize, longestEdge edge: CGFloat) -> NSSize {
        let size = scaled(aspect, toLongestEdge: edge)
        let minimum = minimumContentSize(for: aspect)
        guard size.width < minimum.width || size.height < minimum.height else { return size }
        return minimum
    }

    /// `size` shrunk to fit inside `available`, keeping its proportions. Sizes that
    /// already fit are returned untouched — this only ever makes the window smaller.
    static func fitted(_ size: NSSize, in available: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0
        else { return size }

        let scale = min(available.width / size.width, available.height / size.height)
        return scale < 1 ? multiply(size, by: scale) : size
    }

    /// The size an empty player opens at: as big as it was last time, in the default shape.
    ///
    /// How big is remembered, what shape is not. There is no video on an empty player, so
    /// there is nothing to take proportions from, and keeping the shape of whatever played
    /// last time would leave a placeholder sitting in a tall thin window for no reason. The
    /// shape becomes the video's the moment one is opened.
    static func blankContentSize(remembering size: NSSize?) -> NSSize {
        let edge = size.map { max($0.width, $0.height) } ?? Layout.preferredLongestEdge
        return shaped(like: Layout.defaultContentSize, longestEdge: edge)
    }

    /// The size a reset returns the player to: the default longest edge, in the shape the
    /// player already has.
    ///
    /// A reset forgets how big you made the window, but not what is playing in it, so the
    /// shape still belongs to the open video. Forcing 16:9 back on a portrait video would
    /// letterbox it, which is a worse state than the one being reset from. An empty player
    /// is already 16:9, so it lands on `Layout.defaultContentSize` either way.
    static func resetContentSize(shapedLike aspect: NSSize) -> NSSize {
        guard aspect.width > 0, aspect.height > 0 else { return Layout.defaultContentSize }
        return shaped(like: aspect, longestEdge: Layout.preferredLongestEdge)
    }

    /// `size` grown to the floor for its own shape if it is under it.
    ///
    /// Used on sizes arriving from outside the app — a remembered size from a previous
    /// launch — where the value cannot be assumed to be one we would have produced.
    static func clampedToMinimum(_ size: NSSize) -> NSSize {
        let minimum = minimumContentSize(for: size)
        return NSSize(
            width: max(size.width, minimum.width),
            height: max(size.height, minimum.height)
        )
    }

    /// Rounded to whole points: a fractional window size lands the video on half a pixel
    /// and softens the whole frame.
    private static func multiply(_ size: NSSize, by scale: CGFloat) -> NSSize {
        NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
