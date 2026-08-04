import AppKit

/// Look shared by the two collapse controls, so the icon on a standing player and the tab on
/// a collapsed one read as the same control in two places rather than as two controls.
enum CollapseChrome {
    /// Opaque enough to read over a bright video, muted enough to ignore over a dark one.
    static let fill = NSColor(white: 0.42, alpha: 0.92)
    static let hoveredFill = NSColor(white: 0.55, alpha: 0.96)
    static let glyph = NSColor(white: 0.96, alpha: 1)
    static let glyphLineWidth: CGFloat = 1.6

    /// A chevron pointing left or right, centred on `centre`.
    static func chevron(at centre: NSPoint, width: CGFloat, height: CGFloat, pointsRight: Bool)
        -> NSBezierPath
    {
        let tipX = centre.x + (pointsRight ? width / 2 : -width / 2)
        let backX = centre.x + (pointsRight ? -width / 2 : width / 2)

        let path = NSBezierPath()
        path.move(to: NSPoint(x: backX, y: centre.y + height / 2))
        path.line(to: NSPoint(x: tipX, y: centre.y))
        path.line(to: NSPoint(x: backX, y: centre.y - height / 2))
        path.lineWidth = glyphLineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}

/// Base for the two controls: a rounded grey plate that takes a click and knows nothing else.
///
/// The clicking is the whole reason both exist. Neither ever responds to the cursor merely
/// being nearby, which is what separates collapsing in Normal Player from what Peek does on
/// its own.
class CollapseControl: NSView {
    /// Called when the control is clicked. The view decides nothing itself: which way the
    /// player then moves is the controller's business.
    var onClick: (() -> Void)?

    /// Which screen edge the player collapses against, and whether it is there now. Together
    /// they settle which way the glyph points.
    var side: CollapseResolver.Side = .right {
        didSet {
            guard side != oldValue else { return }
            needsDisplay = true
        }
    }

    var isCollapsed = false {
        didSet {
            guard isCollapsed != oldValue else { return }
            needsDisplay = true
        }
    }

    fileprivate var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }

    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CollapseControl is created in code only")
    }

    /// The window is always on top and almost never the frontmost app, so a click here is
    /// usually the click that would otherwise be spent activating SmartPiP. Taking it means
    /// the control works on the first click rather than the second.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Kept out of the window drag. The rest of the player moves the window when you press on
    /// it, and these are the parts of it that must not.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// Swallowed so a press that wanders does not fall through to the window drag behind it.
    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {}

    /// Lights up under the pointer, so an always-visible control still reads as a button.
    ///
    /// This is the only place in the app where hovering does anything, and it changes nothing
    /// but a colour. The window itself never moves because of it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// Which way the glyph points, which is also the way the player will travel.
    fileprivate var pointsRight: Bool {
        switch side {
        case .right: !isCollapsed
        case .left: isCollapsed
        }
    }

    fileprivate func fillPlate(cornerRadius: CGFloat) {
        (isHovered ? CollapseChrome.hoveredFill : CollapseChrome.fill).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}

/// The small grey tab left behind when the player is collapsed.
///
/// It sits on the window's inner edge, which is what makes the whole thing work with one
/// control: collapsing slides the window out until only the tab's width is left on screen, so
/// the tab arrives flush against the edge and stays the one part you can still reach. Nothing
/// appears and nothing moves to a new place.
///
/// Shown only while the player is collapsed. On a standing player the affordance is
/// `CollapseIconView` in the corner instead, because a full height bar down the side of the
/// picture is a lot of furniture for a control you use occasionally.
final class CollapseTabView: CollapseControl {
    private enum Metrics {
        static let cornerRadius: CGFloat = 3
        /// Glyph size as a fraction of the tab, so it stays in proportion if the tab is ever
        /// resized.
        static let chevronWidthRatio: CGFloat = 0.3
        static let chevronHeightRatio: CGFloat = 0.22
    }

    override func draw(_ dirtyRect: NSRect) {
        fillPlate(cornerRadius: Metrics.cornerRadius)

        CollapseChrome.glyph.setStroke()
        CollapseChrome.chevron(
            at: NSPoint(x: bounds.midX, y: bounds.midY),
            width: bounds.width * Metrics.chevronWidthRatio,
            height: bounds.height * Metrics.chevronHeightRatio,
            pointsRight: pointsRight
        ).stroke()
    }
}

/// The collapse button in the top corner of a standing normal player.
///
/// Carries Peek's own menu bar symbol, taken from `PlayerMode.peek` so the two cannot drift:
/// pressing this puts the player exactly where Peek would put it, and one picture for one
/// placement is easier to learn than two.
///
/// Deliberately neutral about direction, unlike the tab. The tab is a way back and says
/// which way that is; this is a name for a place, and a button whose arrow turned around
/// depending on which half of the screen the window happened to be in would read as two
/// different buttons.
///
/// Top left, where macOS keeps window chrome, and clear of the transport controls along the
/// bottom. Hidden as soon as the player collapses: only a tab's width of the window is on
/// screen then, and a corner button would be sliced in half by the screen edge.
final class CollapseIconView: CollapseControl {
    private enum Metrics {
        static let cornerRadius: CGFloat = 5
        static let symbolPointSize: CGFloat = 12
    }

    /// Rendered once. The glyph never changes, so there is nothing to rebuild per draw.
    private static let symbol: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: Metrics.symbolPointSize, weight: .medium
        ).applying(NSImage.SymbolConfiguration(hierarchicalColor: CollapseChrome.glyph))

        return NSImage(
            systemSymbolName: PlayerMode.peek.statusSymbolName,
            accessibilityDescription: PlayerMode.peek.menuTitle
        )?.withSymbolConfiguration(configuration)
    }()

    override func draw(_ dirtyRect: NSRect) {
        fillPlate(cornerRadius: Metrics.cornerRadius)

        guard let symbol = Self.symbol else { return }
        let size = symbol.size
        symbol.draw(
            in: NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height))
    }
}
