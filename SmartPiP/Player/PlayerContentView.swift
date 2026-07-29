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

    init(playerView: AVPlayerView) {
        self.playerView = playerView
        super.init(frame: NSRect(origin: .zero, size: Layout.defaultContentSize))

        wantsLayer = true

        placeholderLabel.stringValue = "Drop a MOV or MP4 here"
        placeholderLabel.alignment = .center
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 2

        for subview in [playerView, placeholderLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor, constant: Metrics.placeholderInset),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -Metrics.placeholderInset),
        ])

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PlayerContentView is created in code only")
    }

    /// Hides the "drop a file here" hint once something is playing.
    var showsPlaceholder: Bool {
        get { !placeholderLabel.isHidden }
        set { placeholderLabel.isHidden = !newValue }
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
        isDropTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDropTargeted = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isDropTargeted = false
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        droppableURL(from: sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDropTargeted = false
        guard let url = droppableURL(from: sender) else { return false }
        delegate?.playerContentView(self, didReceiveFileAt: url)
        return true
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
