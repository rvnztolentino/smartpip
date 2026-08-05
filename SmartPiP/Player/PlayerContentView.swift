import AppKit
import AVKit

@MainActor
protocol PlayerContentViewDelegate: AnyObject {
    func playerContentView(_ view: PlayerContentView, didReceiveFileAt url: URL)
    func playerContentViewDidClickCollapseControl(_ view: PlayerContentView)
}

/// Content view of the player window: hosts the `AVPlayerView` and acts as the
/// drag-and-drop destination for video files.
///
/// The drop target lives here rather than on the `AVPlayerView` because AppKit
/// walks up the superview chain to find a registered dragging destination, so a
/// drop anywhere over the player still lands on this view.
final class PlayerContentView: NSView {
    private enum Metrics {
        static let dropBorderWidth: CGFloat = 3
        static let dropBorderInset: CGFloat = 1.5
        static let placeholderInset: CGFloat = 12
        /// Enough for the longest message at the smallest window size. Past this the last
        /// line truncates, which is better than text running out of the window.
        static let messageLineLimit = 4
        /// Any value above the video view's layer is enough; 1 keeps it obvious.
        static let messageZPosition: CGFloat = 1
    }

    weak var delegate: PlayerContentViewDelegate?

    private let playerView: AVPlayerView
    private let placeholderLabel = NSTextField(labelWithString: "")
    private let collapseTab = CollapseTabView(frame: .zero)
    private let collapseIcon = CollapseIconView(frame: .zero)

    private var collapseControls: [CollapseControl] { [collapseTab, collapseIcon] }

    /// Which screen edge the player collapses against, and whether it is there now. The
    /// controller works both out; the view only has to draw and place the controls
    /// accordingly.
    var collapseSide: CollapseResolver.Side = .right {
        didSet {
            guard collapseSide != oldValue else { return }
            collapseControls.forEach { $0.side = collapseSide }
            needsLayout = true
        }
    }

    var isCollapsed = false {
        didSet { collapseControls.forEach { $0.isCollapsed = isCollapsed } }
    }

    /// The tab left behind on a collapsed player, and the button in the corner of a standing
    /// one. Never both: they are one control in two places, and each belongs to the state the
    /// other cannot be reached in.
    ///
    /// The controller decides. In Peek the tab is shown without either being clickable, since
    /// there the cursor is the control and a button that did nothing would be worse than no
    /// button at all.
    var showsCollapseTab = false {
        didSet { collapseTab.isHidden = !showsCollapseTab }
    }

    var showsCollapseIcon = true {
        didSet { collapseIcon.isHidden = !showsCollapseIcon }
    }

    private var isDropTargeted = false {
        didSet {
            guard isDropTargeted != oldValue else { return }
            needsDisplay = true
        }
    }

    /// What the player is currently doing, so the view can explain why a drop is being
    /// refused, and stop explaining the moment the override key makes it possible.
    ///
    /// Held here rather than asked for on demand because the message has to be right the
    /// moment a drag arrives, and a drag arrives without warning.
    var behaviour = PlayerBehaviour(mode: .default) {
        didSet {
            guard behaviour != oldValue else { return }
            isShowingModeAdvice = false
            updateMessage()
        }
    }

    /// Set while a refused drag is hovering, so the explanation can appear over a video
    /// that is already playing — the placeholder alone would only ever be seen on an
    /// empty player, which is not when people discover the restriction.
    private var isShowingModeAdvice = false {
        didSet {
            guard isShowingModeAdvice != oldValue else { return }
            updateMessage()
        }
    }

    init(playerView: AVPlayerView) {
        self.playerView = playerView
        super.init(frame: NSRect(origin: .zero, size: Layout.defaultContentSize))

        wantsLayer = true

        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = Metrics.messageLineLimit
        placeholderLabel.cell?.truncatesLastVisibleLine = true

        // The text must never influence the window's size. A window laid out with
        // constraints will not shrink below its content's fitting size, so a label that
        // resists compression becomes a floor on the whole player: longer text would make
        // the window taller and take it off the video's aspect ratio. Dropping both
        // priorities lets the text wrap and clip inside whatever size the window already
        // is, which is the only direction this relationship should run.
        placeholderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        placeholderLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        placeholderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        placeholderLabel.setContentHuggingPriority(.defaultLow, for: .vertical)

        for subview in [playerView, placeholderLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        // Insurance, not a fix for anything observed: the message is also shown over a
        // playing video, and `AVPlayerView` composites its picture through a layer of its
        // own. Being the later subview should be enough to stay in front of it; saying so
        // explicitly costs one line and removes the question.
        placeholderLabel.wantsLayer = true
        placeholderLabel.layer?.zPosition = Metrics.messageZPosition

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Ceilings, not the label's own size: it is kept inside the window rather
            // than being allowed to define it.
            placeholderLabel.widthAnchor.constraint(
                lessThanOrEqualTo: widthAnchor, constant: -Metrics.placeholderInset * 2),
            placeholderLabel.heightAnchor.constraint(
                lessThanOrEqualTo: heightAnchor, constant: -Metrics.placeholderInset * 2),
        ])

        // Added last so they sit in front of the picture and take their own clicks.
        // Positioned in `layout()` rather than by constraints, because which edge they belong
        // on changes with the corner, and a pair of constraints being swapped for each other
        // is a worse way to say the same thing.
        for control in collapseControls {
            control.translatesAutoresizingMaskIntoConstraints = true
            control.onClick = { [weak self] in
                guard let self else { return }
                delegate?.playerContentViewDidClickCollapseControl(self)
            }
            addSubview(control)
        }
        collapseTab.isHidden = !showsCollapseTab

        registerForDraggedTypes([.fileURL])
        updateMessage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PlayerContentView is created in code only")
    }

    /// Whether the player is still empty. Set false once something is playing.
    var showsPlaceholder: Bool = true {
        didSet {
            guard showsPlaceholder != oldValue else { return }
            updateMessage()
        }
    }

    /// Chooses what the label says, or hides it.
    ///
    /// Three cases, in order of precedence: a drag being refused right now, an empty
    /// player, and a player with something in it. An empty player in a mode that refuses
    /// drops shows the advice rather than "drop a file here", because there dropping a file
    /// is exactly what will not work. Holding the override key removes the advice, because
    /// then it does.
    private func updateMessage() {
        let advice = behaviour.directManipulationAdvice

        if isShowingModeAdvice, let advice {
            placeholderLabel.stringValue = advice
            // Over a playing video, secondary grey on its own is unreadable.
            placeholderLabel.drawsBackground = true
            placeholderLabel.backgroundColor = NSColor.black.withAlphaComponent(0.75)
            placeholderLabel.textColor = .labelColor
            placeholderLabel.isHidden = false
            return
        }

        placeholderLabel.drawsBackground = false
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.isHidden = !showsPlaceholder
        placeholderLabel.stringValue = showsPlaceholder
            ? (advice ?? "Drop a MOV or MP4 here")
            : ""
    }

    /// Says the black background is something you may drag the window by, which is what you
    /// get hold of on an empty player. `PlayerWindow.sendEvent` reads this and does the
    /// moving; the system is never asked, because its drag offers to tile the window against
    /// a screen edge.
    override var mouseDownCanMoveWindow: Bool { true }

    /// So a press on an inactive player is not spent activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Resize pointer

    /// The edges the pointer is over, and nil when it is over none of them or the player is
    /// not one you may resize.
    ///
    /// Kept so the cursor is only ever touched when the answer changes. Setting it on every
    /// sample would be sixty pointless calls a second across the middle of a video, and
    /// putting the arrow back is only ours to do when we were the ones who took it away.
    private var pointerEdges: ResizeEdge?

    private var pointerArea: NSTrackingArea?

    /// Whether a press near an edge would resize the player right now.
    ///
    /// Asked of the window rather than worked out from `behaviour` and `isCollapsed` here,
    /// even though both are to hand. It is the same question the press itself asks, and the
    /// pointer promising a resize that the press then refuses is worse than no pointer at
    /// all, so there is one place to ask it.
    private var canResize: Bool {
        (window as? PlayerWindow)?.resizeLimits?() != nil
    }

    /// Watches the pointer so the resize band can announce itself.
    ///
    /// `.activeAlways` because SmartPiP is almost never the frontmost app: a cursor that only
    /// changed while the app was active would never change at all. This is also why the
    /// window's own `mouseMoved` is no use here, and why cursor rectangles are not either.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(at: convert(event.locationInWindow, from: nil))
    }

    /// The pointer has left the player, so whatever it shows now is somebody else's business.
    override func mouseExited(with event: NSEvent) {
        updatePointer(at: nil)
    }

    private func updatePointer(at point: NSPoint?) {
        let edges = point.flatMap { point -> ResizeEdge? in
            guard canResize else { return nil }
            let edges = ResizeResolver.edges(
                at: point, in: bounds.size, border: Layout.resizeBorderWidth)
            return edges.isEmpty ? nil : edges
        }

        guard edges != pointerEdges else { return }
        pointerEdges = edges
        (edges?.cursor ?? .arrow).set()
    }

    override func layout() {
        // Wrapping has to be measured against the window's width, not the label's
        // unconstrained intrinsic width, or a long message lays itself out as one very
        // wide line and then gets clipped instead of wrapping.
        placeholderLabel.preferredMaxLayoutWidth = max(
            bounds.width - Metrics.placeholderInset * 2, 1)

        // The tab lives on the inner edge: the side facing the middle of the screen, which
        // is the opposite one to the edge the player collapses against. That is what leaves
        // it flush against the screen edge, and still the only part in view, once collapsed.
        let tabWidth = min(Layout.collapseTabWidth, bounds.width)
        let tabHeight = min(Layout.collapseTabHeight, bounds.height)
        collapseTab.frame = NSRect(
            x: collapseSide == .right ? bounds.minX : bounds.maxX - tabWidth,
            y: bounds.midY - tabHeight / 2,
            width: tabWidth,
            height: tabHeight
        )

        // The button sits in the top left, inset from both edges, wherever the player is
        // parked and whichever way it collapses. Only the glyph inside it turns around.
        let icon = min(Layout.collapseIconSize, min(bounds.width, bounds.height))
        let inset = min(Layout.collapseIconInset, max((min(bounds.width, bounds.height) - icon) / 2, 0))
        collapseIcon.frame = NSRect(
            x: bounds.minX + inset,
            y: bounds.maxY - inset - icon,
            width: icon,
            height: icon
        )

        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard isDropTargeted else { return }
        let border = bounds.insetBy(dx: Metrics.dropBorderInset, dy: Metrics.dropBorderInset)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: border)
        path.lineWidth = Metrics.dropBorderWidth
        path.stroke()
    }

    // MARK: - Dragging destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    /// Answers again on every update rather than standing by what `draggingEntered` said.
    ///
    /// The refusal message tells you to hold the override key, and you can only do that
    /// after the drag has already arrived. Without this the answer would be fixed at the
    /// moment the file crossed the edge of the window, and taking the advice would do
    /// nothing at all.
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard droppableURL(from: sender) != nil else { return [] }

        // Refused rather than allowed-if-you-are-quick: in Avoid the window is running
        // from the pointer that is holding the file, so a drop is a race. Saying no and
        // saying why is more use than a drop that lands one time in three.
        guard behaviour.acceptsDirectManipulation else {
            isDropTargeted = false
            isShowingModeAdvice = true
            return []
        }

        isShowingModeAdvice = false
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endDrag()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        endDrag()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        behaviour.acceptsDirectManipulation && droppableURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        endDrag()
        guard behaviour.acceptsDirectManipulation, let url = droppableURL(from: sender) else {
            return false
        }
        delegate?.playerContentView(self, didReceiveFileAt: url)
        return true
    }

    private func endDrag() {
        isDropTargeted = false
        isShowingModeAdvice = false
    }

    /// First dragged item that is a local file of a type we can play.
    private func droppableURL(from sender: any NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: VideoFile.contentTypeIdentifiers,
        ]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }
}
