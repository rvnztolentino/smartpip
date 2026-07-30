import AppKit
import QuartzCore

/// Owns the floating player window and everything about where it sits.
///
/// The window has exactly four legal positions. Every path that changes size or
/// position funnels through `applyPlacement(animated:)`, so the window can never
/// end up somewhere that isn't a corner.
@MainActor
final class PlayerWindowController: NSWindowController {
    private(set) var corner: ScreenCorner = .bottomRight
    private(set) var mode: PlayerMode = .default

    /// Called after `mode` changes, so the menu bar item can follow along.
    var onModeChange: ((PlayerMode) -> Void)?

    private let playback: PlaybackController
    private let contentView: PlayerContentView
    private var cursorTracker: CursorTracker?
    private var isCursorOverWindow = false
    private var avoidance = AvoidanceTrigger()

    init() {
        let playback = PlaybackController()
        let contentView = PlayerContentView(playerView: playback.playerView)
        let window = PlayerWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultContentSize))

        self.playback = playback
        self.contentView = contentView
        super.init(window: window)

        window.contentView = contentView
        window.delegate = self
        contentView.delegate = self

        cursorTracker = CursorTracker { [weak self] point in
            self?.cursorSampled(at: point)
        }

        applyPlacement(animated: false)
        applyMode(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PlayerWindowController is created in code only")
    }

    // MARK: - Opening files

    /// Shows a standard open panel restricted to the file types we can play.
    func presentOpenPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFile.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a local MOV or MP4 file."
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    /// Loads `url`, then resizes the window to the video and re-parks it.
    func open(_ url: URL) {
        guard VideoFile.isSupported(url) else {
            NSSound.beep()
            return
        }

        contentView.showsPlaceholder = false

        Task { [weak self] in
            guard let self else { return }
            let videoSize = await playback.load(url)
            apply(contentSize: Self.contentSize(forVideo: videoSize), animated: false)
        }
    }

    // MARK: - Mode

    /// Switches `mode` on, or off if it is already on.
    ///
    /// Avoid and Lock are one choice, so asking for one switches the other off. Both
    /// menu items go through here, which is what keeps at most one of them ticked.
    func toggle(_ mode: PlayerMode) {
        setMode(self.mode.toggled(mode))
    }

    func setMode(_ newMode: PlayerMode) {
        guard newMode != mode else { return }
        mode = newMode
        applyMode(animated: true)
        onModeChange?(newMode)
    }

    /// Locking does not dim on its own — the window only fades while the cursor is
    /// actually over it. Unlocking does not steal focus either; clicking the window
    /// does that.
    private func applyMode(animated: Bool) {
        guard let window else { return }

        window.ignoresMouseEvents = mode.isClickThrough
        playback.setControlsVisible(mode.showsTransportControls)

        if mode.needsCursorTracking {
            cursorTracker?.start()
        } else {
            cursorTracker?.stop()
            isCursorOverWindow = false
        }

        applyOpacity(animated: animated)

        // A mode change is a deliberate act, so judge it on where the cursor is now
        // rather than inheriting a disarm from the last dodge. Sampling here as well
        // makes the toggle land immediately: switching from Lock to Avoid leaves the
        // tracker already running, so nothing else would look at the cursor until
        // its next tick.
        avoidance.rearm()
        if mode.avoidsCursor {
            updateAvoidance(for: NSEvent.mouseLocation)
        }
    }

    // MARK: - Cursor proximity

    private func cursorSampled(at point: NSPoint) {
        updateHoverFade(for: point)
        updateAvoidance(for: point)
    }

    /// Fade only applies to a locked player: that is when you cannot move the window
    /// out of the way by hand, so seeing through it is the only option.
    private var targetAlpha: CGFloat {
        mode.isClickThrough && isCursorOverWindow ? Layout.hoveredWindowAlpha : 1
    }

    private func updateHoverFade(for point: NSPoint) {
        guard let window else { return }

        // Asymmetric bounds: the cursor has to clear the frame by a small margin
        // before the window comes back, so resting on an edge does not flicker.
        let bounds = isCursorOverWindow
            ? window.frame.insetBy(dx: -Layout.hoverHysteresis, dy: -Layout.hoverHysteresis)
            : window.frame

        let isOver = bounds.contains(point)
        guard isOver != isCursorOverWindow else { return }
        isCursorOverWindow = isOver
        applyOpacity(animated: true)
    }

    // MARK: - Avoidance

    /// Runs the window away from an approaching cursor.
    ///
    /// Driven from the global cursor poll rather than the window's own
    /// mouse-entered events: the window moves out from under the cursor, which
    /// would immediately fire `mouseExited` and start a loop.
    private func updateAvoidance(for point: NSPoint) {
        guard mode.avoidsCursor,
              let window,
              let visibleFrame = currentVisibleFrame()
        else { return }

        let distance = AvoidanceResolver.distance(from: point, to: window.frame)
        guard avoidance.shouldFlee(distance: distance) else { return }

        move(to: AvoidanceResolver.destination(
            from: corner,
            size: window.frame.size,
            cursor: point,
            visibleFrame: visibleFrame,
            margin: Layout.cornerMargin))
    }

    private func applyOpacity(animated: Bool) {
        guard let window else { return }
        let alpha = targetAlpha
        guard window.alphaValue != alpha else { return }

        guard animated else {
            window.alphaValue = alpha
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.opacityFadeDuration
            window.animator().alphaValue = alpha
        }
    }

    // MARK: - Playback

    func togglePlayPause() {
        playback.togglePlayPause()
    }

    var canTogglePlayPause: Bool {
        playback.hasVideo
    }

    // MARK: - Placement

    /// Moves the window one corner clockwise.
    func cycleCorner() {
        move(to: corner.next)
    }

    func move(to corner: ScreenCorner) {
        self.corner = corner

        // Every animated move — dodge or manual cycle — puts the window in flight
        // across the screen, so hold avoidance off until it has landed.
        if Preferences.shared.animatesCornerTransition {
            avoidance.windowIsMoving(
                until: Date().addingTimeInterval(Layout.cornerAnimationDuration))
        }

        applyPlacement(animated: true)
    }

    private func applyPlacement(animated: Bool) {
        guard let window else { return }
        apply(frameSize: window.frame.size, animated: animated)
    }

    private func apply(contentSize: NSSize, animated: Bool) {
        guard let window else { return }
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)).size
        apply(frameSize: frameSize, animated: animated)
    }

    private func apply(frameSize: NSSize, animated: Bool) {
        guard let window, let visibleFrame = currentVisibleFrame() else { return }
        let target = corner.frame(
            for: frameSize, in: visibleFrame, margin: Layout.cornerMargin)

        guard animated, Preferences.shared.animatesCornerTransition else {
            window.setFrame(target, display: true)
            return
        }

        // Hand the move to Core Animation rather than nudging the frame on a
        // timer — the compositor does this work for free.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.cornerAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: false)
        }
    }

    private func currentVisibleFrame() -> NSRect? {
        (window?.screen ?? NSScreen.main)?.visibleFrame
    }

    /// Scales `videoSize` down to a small player, without going under the
    /// minimum window size.
    private static func contentSize(forVideo videoSize: NSSize?) -> NSSize {
        guard let videoSize, videoSize.width > 0, videoSize.height > 0 else {
            return Layout.defaultContentSize
        }

        let scale = Layout.preferredLongestEdge / max(videoSize.width, videoSize.height)
        var size = NSSize(
            width: (videoSize.width * scale).rounded(),
            height: (videoSize.height * scale).rounded()
        )

        let minimum = Layout.minimumContentSize
        if size.width < minimum.width || size.height < minimum.height {
            let upscale = max(minimum.width / size.width, minimum.height / size.height)
            size = NSSize(
                width: (size.width * upscale).rounded(),
                height: (size.height * upscale).rounded()
            )
        }

        return size
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        // Menu bar, Dock or display arrangement changed — the corner we are in
        // may no longer be where we think it is.
        applyPlacement(animated: false)
    }
}

// MARK: - NSWindowDelegate

extension PlayerWindowController: NSWindowDelegate {
    func windowDidEndLiveResize(_ notification: Notification) {
        // Resizing from a leading edge drags the origin with it; re-anchor so we
        // stay flush in the current corner.
        applyPlacement(animated: false)
    }
}

// MARK: - PlayerContentViewDelegate

extension PlayerWindowController: PlayerContentViewDelegate {
    func playerContentView(_ view: PlayerContentView, didReceiveFileAt url: URL) {
        open(url)
    }
}
