import AppKit
import QuartzCore

/// Owns the floating player window and everything about where it sits.
///
/// The window has exactly four legal positions. Every path that changes size or
/// position funnels through `applyPlacement(animated:)`, so the window can never
/// end up somewhere that isn't a corner.
@MainActor
final class PlayerWindowController: NSWindowController {
    /// Written back to `Preferences` on every change rather than at quit, from a `didSet`
    /// rather than by hand at each call site, so a new way to move the window cannot
    /// forget to record where it went.
    private(set) var corner: ScreenCorner {
        didSet { Preferences.shared.corner = corner }
    }

    private(set) var mode: PlayerMode {
        didSet { Preferences.shared.mode = mode }
    }

    /// Called after `mode` changes, so the menu bar item can follow along.
    var onModeChange: ((PlayerMode) -> Void)?

    private let playback: PlaybackController
    private let contentView: PlayerContentView
    private var cursorTracker: CursorTracker?
    private var isCursorOverWindow = false
    private var avoidance = AvoidanceTrigger()
    private var dragReleaseWatch: Timer?

    init() {
        // Read the remembered state before anything is built: the mode decides whether
        // the transport controls are there to begin with, which avoids a frame of
        // controls appearing and then being taken away again.
        let mode = Preferences.shared.mode
        let contentSize = WindowSizing.blankContentSize(
            remembering: Preferences.shared.contentSize)

        let playback = PlaybackController(controlsVisible: mode.showsTransportControls)
        let contentView = PlayerContentView(playerView: playback.playerView)
        let window = PlayerWindow(contentRect: NSRect(origin: .zero, size: contentSize))

        self.corner = Preferences.shared.corner
        self.mode = mode
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
            apply(
                contentSize: WindowSizing.contentSize(
                    forVideo: videoSize, currentLongestEdge: currentLongestContentEdge),
                animated: false)
        }
    }

    // MARK: - Mode

    /// Selects `newMode`. Selecting the mode already in effect does nothing.
    ///
    /// The three modes are one choice with three options, so this is the only mode entry
    /// point: every menu item and every shortcut selects a mode outright rather than
    /// toggling one. Nothing can leave the player with no mode, and nothing can leave two
    /// of them ticked.
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

        // Dragging and resizing are only offered to a normal player. In the other two
        // modes the window is meant to be out of the way, and a mode change mid-drag
        // would otherwise leave a drag in progress on a window that no longer accepts it.
        let manipulable = mode.acceptsDirectManipulation
        window.isMovable = manipulable
        window.isMovableByWindowBackground = manipulable
        contentView.mode = mode
        if !manipulable {
            endDragReleaseWatch()
        }

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

    // MARK: - Reset

    /// Puts the player back to how it starts on a fresh install: bottom right, avoiding the
    /// cursor, at the default size, with corner moves animated again.
    ///
    /// Whatever is playing keeps playing. Everything reset here is a window setting, and
    /// closing the video would make an undo of the window state also throw away the file
    /// you had open, which is not what the menu item says it does.
    func resetSettings() {
        Preferences.shared.resetToDefaults()

        if mode != .default {
            mode = .default
            applyMode(animated: true)
            onModeChange?(mode)
        }

        // One animated move rather than a corner change followed by a resize: two
        // animations on the same window at the same time fight over its frame.
        corner = .default
        holdAvoidanceDuringMove()
        apply(
            contentSize: WindowSizing.resetContentSize(shapedLike: currentContentSize),
            animated: true)
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
        holdAvoidanceDuringMove()
        applyPlacement(animated: true)
    }

    /// Every animated move — dodge, manual cycle or reset — puts the window in flight
    /// across the screen, so hold avoidance off until it has landed.
    private func holdAvoidanceDuringMove() {
        guard Preferences.shared.animatesCornerTransition else { return }
        avoidance.windowIsMoving(
            until: Date().addingTimeInterval(Layout.cornerAnimationDuration))
    }

    private func applyPlacement(animated: Bool) {
        guard let window else { return }
        apply(frameSize: window.frame.size, animated: animated)
    }

    // MARK: - Dragging to a corner

    /// Watches for the end of a window drag, then parks the window in the corner it was
    /// dragged towards.
    ///
    /// AppKit has no "did end dragging" callback to pair with `windowDidMove`, and the
    /// last move notification arrives while the button is still down, so the release has
    /// to be noticed some other way. This polls the button state for the same reasons
    /// `CursorTracker` polls the pointer: no permission prompt, and no event monitor to
    /// be starved by the modal loop AppKit runs during the drag.
    private func beginDragReleaseWatch() {
        guard dragReleaseWatch == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons == 0 else { return }
                self.endDragReleaseWatch()
                self.snapToNearestCorner()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragReleaseWatch = timer
    }

    private func endDragReleaseWatch() {
        dragReleaseWatch?.invalidate()
        dragReleaseWatch = nil
    }

    private func snapToNearestCorner() {
        guard let window, let visibleFrame = currentVisibleFrame() else { return }
        let centre = NSPoint(x: window.frame.midX, y: window.frame.midY)
        move(to: ScreenCorner.nearest(to: centre, in: visibleFrame))
    }

    private func apply(contentSize: NSSize, animated: Bool) {
        guard let window else { return }
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)).size
        apply(frameSize: frameSize, animated: animated)
    }

    private func apply(frameSize: NSSize, animated: Bool) {
        guard let window, let visibleFrame = currentVisibleFrame() else { return }

        // Shrink to fit before parking rather than letting the corner clamp each edge
        // separately: independent clamping squashes an oversized window into a different
        // shape, which is exactly what the aspect lock exists to prevent.
        let available = NSSize(
            width: visibleFrame.width - Layout.cornerMargin * 2,
            height: visibleFrame.height - Layout.cornerMargin * 2
        )
        let fitted = WindowSizing.fitted(frameSize, in: available)
        applySizeConstraints(forFrameSize: fitted)

        let target = corner.frame(
            for: fitted, in: visibleFrame, margin: Layout.cornerMargin)

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

    /// Pins the window's shape to whatever it is being sized to, and records that size.
    ///
    /// `contentAspectRatio` is what makes a drag on any edge keep the video's proportions,
    /// so it has to be reset whenever a new file changes the shape. `contentMinSize` moves
    /// with it: a floor of a different shape to the ratio would leave AppKit reconciling
    /// two contradictory constraints during a resize.
    ///
    /// This is also where the remembered size is written, because every path that changes
    /// the window's size arrives here.
    private func applySizeConstraints(forFrameSize frameSize: NSSize) {
        guard let window else { return }
        let contentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        window.contentAspectRatio = contentSize
        window.contentMinSize = WindowSizing.minimumContentSize(for: contentSize)
        Preferences.shared.contentSize = contentSize
    }

    /// The content area as it stands, which is also the player's current shape: 16:9 while
    /// empty, the video's proportions once one is open.
    private var currentContentSize: NSSize {
        guard let window else { return Layout.defaultContentSize }
        return window.contentRect(forFrameRect: window.frame).size
    }

    /// Longest edge of the current content area, which a newly opened video is resized
    /// to match so it inherits the size the player already has.
    private var currentLongestContentEdge: CGFloat {
        guard window != nil else { return Layout.preferredLongestEdge }
        return max(currentContentSize.width, currentContentSize.height)
    }

    private func currentVisibleFrame() -> NSRect? {
        (window?.screen ?? NSScreen.main)?.visibleFrame
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

    /// Refuses a resize outright unless the player is normal.
    ///
    /// `isMovable` covers dragging but there is no equivalent flag for resizing, and
    /// `.resizable` cannot simply be dropped from a borderless window's style mask
    /// without rebuilding it. Returning the current size is the supported way to say no.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        mode.acceptsDirectManipulation ? frameSize : sender.frame.size
    }

    func windowDidMove(_ notification: Notification) {
        // Fires for our own animated corner moves as well as for a user drag, so only
        // arm the snap while a button is actually down.
        guard mode.acceptsDirectManipulation, NSEvent.pressedMouseButtons != 0 else { return }
        beginDragReleaseWatch()
    }
}

// MARK: - PlayerContentViewDelegate

extension PlayerWindowController: PlayerContentViewDelegate {
    func playerContentView(_ view: PlayerContentView, didReceiveFileAt url: URL) {
        open(url)
    }
}
