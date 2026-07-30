import AppKit
import AVKit

@MainActor
protocol PlayerContentViewDelegate: AnyObject {
    func playerContentView(_ view: PlayerContentView, didReceiveFileAt url: URL)
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

    private var isDropTargeted = false {
        didSet {
            guard isDropTargeted != oldValue else { return }
            needsDisplay = true
        }
    }

    /// The current mode, so the view can explain why a drop is being refused.
    ///
    /// Held here rather than asked for on demand because the message has to be right the
    /// moment a drag arrives, and a drag arrives without warning.
    var mode: PlayerMode = .default {
        didSet {
            guard mode != oldValue else { return }
            isShowingModeAdvice = false
            updateMessage()
        }
    }

    /// Set while a refused drag is hovering, so the explanation can appear over a video
    /// that is already playing — the placeholder alone would only ever be seen on an
    /// empty player, which is not when people discover the restriction.
    private var isShowingModeAdvice = false

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
    /// player, and a player with something in it. An empty player in Avoid or Lock shows
    /// the advice rather than "drop a file here", because there dropping a file is exactly
    /// what will not work.
    private func updateMessage() {
        let advice = mode.directManipulationAdvice

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

    /// Drags the window when the press lands on the background rather than on the video,
    /// which is what happens on an empty player.
    override func mouseDown(with event: NSEvent) {
        guard let window, window.isMovable else {
            super.mouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }

    override func layout() {
        // Wrapping has to be measured against the window's width, not the label's
        // unconstrained intrinsic width, or a long message lays itself out as one very
        // wide line and then gets clipped instead of wrapping.
        placeholderLabel.preferredMaxLayoutWidth = max(
            bounds.width - Metrics.placeholderInset * 2, 1)
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
        guard droppableURL(from: sender) != nil else { return [] }

        // Refused rather than allowed-if-you-are-quick: in Avoid the window is running
        // from the pointer that is holding the file, so a drop is a race. Saying no and
        // saying why is more use than a drop that lands one time in three.
        guard mode.acceptsDirectManipulation else {
            isShowingModeAdvice = true
            updateMessage()
            return []
        }

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
        mode.acceptsDirectManipulation && droppableURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        endDrag()
        guard mode.acceptsDirectManipulation, let url = droppableURL(from: sender) else {
            return false
        }
        delegate?.playerContentView(self, didReceiveFileAt: url)
        return true
    }

    private func endDrag() {
        isDropTargeted = false
        guard isShowingModeAdvice else { return }
        isShowingModeAdvice = false
        updateMessage()
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
