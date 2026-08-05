import AppKit
import QuartzCore

/// Owns the floating player window and everything about where it sits.
///
/// The window has four legal positions, one per corner, and one more per corner for a
/// collapsed player resting off the edge beside it. Every path that changes size or position
/// funnels through `applyPlacement(animated:)`, so the window can never end up anywhere
/// else, and only ever leaves its corner when it has been collapsed there on purpose.
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
    ///
    /// The mode, not the behaviour: the menu bar icon says which mode is selected, and a
    /// key being held for a moment does not change that.
    var onModeChange: ((PlayerMode) -> Void)?

    /// True while the override key is held. Never persisted: it is a hold, not a setting.
    private var isOverrideHeld = false

    /// What the player is actually doing, once the held key is taken into account. Every
    /// decision about clicks, controls, movement and manipulation reads this.
    private var behaviour: PlayerBehaviour {
        PlayerBehaviour(mode: mode, isOverridden: isOverrideHeld)
    }

    /// Whether the player is tucked against the screen edge with only its tab in view.
    ///
    /// Where the window *is*, which is not the same as what gets remembered. You set this in
    /// Normal Player and the cursor sets it in Peek, so it is deliberately not written back
    /// from a `didSet`: a peeking player left hidden when you quit must not come back as a
    /// collapsed normal one. `Preferences.isCollapsed` records the choice you made, and
    /// `setCollapsed(_:)` is the only thing that writes it.
    private(set) var isCollapsed: Bool

    private let playback: PlaybackController
    private let contentView: PlayerContentView
    private var cursorTracker: CursorTracker?
    private var isCursorOverWindow = false
    private var avoidance = AvoidanceTrigger()
    private var peek = PeekTrigger()

    init() {
        // Read the remembered state before anything is built: the mode decides whether
        // the transport controls are there to begin with, which avoids a frame of
        // controls appearing and then being taken away again.
        let mode = Preferences.shared.mode
        let contentSize = WindowSizing.blankContentSize(
            remembering: Preferences.shared.contentSize)

        let playback = PlaybackController(
            controlsVisible: PlayerBehaviour(mode: mode).showsTransportControls)
        let contentView = PlayerContentView(playerView: playback.playerView)
        let window = PlayerWindow(contentRect: NSRect(origin: .zero, size: contentSize))

        self.corner = Preferences.shared.corner
        self.mode = mode
        // The remembered collapse is the choice you made in Normal Player, so it only applies
        // when that is the mode coming back. Peek works this out from the cursor a moment
        // later, and the other two are never collapsed at all.
        self.isCollapsed = mode.canCollapse && Preferences.shared.isCollapsed
        self.playback = playback
        self.contentView = contentView
        super.init(window: window)

        window.contentView = contentView
        contentView.delegate = self
        window.canDragWindow = { [weak self] in self?.canDragWindow ?? false }
        window.onDragEnded = { [weak self] in self?.snapToNearestCorner() }
        window.resizeLimits = { [weak self] in self?.resizeLimits }
        window.onResizeEnded = { [weak self] in self?.applyPlacement(animated: false) }

        cursorTracker = CursorTracker { [weak self] point in
            self?.inputSampled(at: point)
        }

        applyPlacement(animated: false)
        applyBehaviour(animated: false)
        rearmAvoidance()

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
        applyBehaviour(animated: true)
        rearmAvoidance()
        onModeChange?(newMode)
    }

    // MARK: - Collapsing

    /// Tucks the player against the nearest screen edge, or brings it back.
    ///
    /// Your way in and out, from either menu or from the control on the window, and the only
    /// path that records the choice. Peek arrives at the same placement from the cursor
    /// instead, and deliberately does not write anything down.
    func toggleCollapse() {
        setCollapsed(!isCollapsed)
    }

    func setCollapsed(_ collapsed: Bool) {
        guard behaviour.canCollapse, collapsed != isCollapsed else { return }
        Preferences.shared.isCollapsed = collapsed
        isCollapsed = collapsed
        collapseDidChange(animated: true)
    }

    var canToggleCollapse: Bool { behaviour.canCollapse }

    /// Settles where the window belongs after a mode change or a press of the override key.
    ///
    /// Three different owners of the same placement, which is why this is one place rather
    /// than a branch at each call site: Peek reads the cursor, Normal Player reads back the
    /// choice you made, and everything else stands in its corner.
    private func applyCollapseState() {
        guard behaviour.peeksFromCursor else {
            peek.reset(hidden: false)
            isCollapsed = behaviour.canCollapse && Preferences.shared.isCollapsed
            return
        }

        // Seeded from where the cursor is rather than from standing out, so switching to Peek
        // with the pointer already on the player tucks it away at once instead of showing it
        // for a tick and then taking it back.
        let hidden = isCursorAtPlayer(NSEvent.mouseLocation, whenHidden: false)
        peek.reset(hidden: hidden)
        isCollapsed = hidden
    }

    // MARK: - Peeking

    /// Tucks a peeking player away as the cursor arrives, and brings it back once it has gone.
    ///
    /// Driven from the poll rather than the window's own tracking areas, for the same reason
    /// as avoidance: the window moves out from under the cursor, so `mouseExited` would fire
    /// on every hide and the two would drive each other.
    private func updatePeek(for point: NSPoint) {
        guard behaviour.peeksFromCursor else { return }

        let hidden = peek.update(
            isCursorAtPlayer: isCursorAtPlayer(point, whenHidden: isCollapsed))
        guard hidden != isCollapsed else { return }

        // Deliberately not `Preferences.isCollapsed`: that records the choice you made in
        // Normal Player, and the cursor moving is not you making it.
        isCollapsed = hidden
        collapseDidChange(animated: true)
    }

    /// Whether the cursor counts as being at the player.
    ///
    /// Standing out, that is the window's own frame. Tucked away it is everywhere the player
    /// would be if it came back, which is a larger region and has to be: the cursor that sent
    /// it away is left sitting exactly where the window used to be, so anything smaller reads
    /// as clear the moment the window leaves and the two states take turns forever.
    ///
    /// Measured from where the window stands rather than from where it is, so the answer does
    /// not move underneath the rule asking for it.
    private func isCursorAtPlayer(_ point: NSPoint, whenHidden hidden: Bool) -> Bool {
        guard let window, let visibleFrame = currentVisibleFrame() else { return false }
        let standing = corner.frame(
            for: window.frame.size, in: visibleFrame, margin: Layout.cornerMargin)

        guard hidden else { return standing.contains(point) }
        return CollapseResolver.occupiedArea(
            standing: standing, in: visibleFrame,
            tab: Layout.collapseTabWidth, margin: Layout.hoverHysteresis
        ).contains(point)
    }

    /// Applies everything that depends on the mode and the override key together.
    ///
    /// Called for a mode change and for a press or release of the override key, because
    /// between them the two settle the same questions: what the window ignores, what it
    /// shows, what it lets you do to it, and whether it is allowed to move at all.
    ///
    /// Locking does not dim on its own — the window only fades while the cursor is
    /// actually over it. Unlocking does not steal focus either; clicking the window
    /// does that.
    private func applyBehaviour(animated: Bool) {
        guard let window else { return }
        let behaviour = self.behaviour

        window.ignoresMouseEvents = behaviour.isClickThrough
        playback.setControlsVisible(behaviour.showsTransportControls)

        contentView.behaviour = behaviour

        if behaviour.needsCursorTracking {
            cursorTracker?.start()
        } else {
            cursorTracker?.stop()
            isCursorOverWindow = false
        }

        applyOpacity(animated: animated)
        applyCollapseState()
        applyCollapseControls()
        applyPlacement(animated: animated)
    }

    /// Whether a press on the player's background moves the window.
    ///
    /// Read by `PlayerWindow` at the moment of the press rather than pushed down on every
    /// change, so it is never stale: the mode, the override key and the placement can all
    /// have moved since the last time anything asked.
    ///
    /// Dragging and resizing are only offered to a player you have full control of: a normal
    /// one, or any of them with the key held. A mode change or a release mid-drag would
    /// otherwise leave a drag in progress on a window that no longer accepts it.
    ///
    /// A collapsed player is excluded whatever its mode. There is a tab's width of it on
    /// screen, so a drag would be a grab at something that is not really there and a resize
    /// would change the shape of a window nobody can see. Dropping a file still works,
    /// because that at least does something you can then look at.
    var canDragWindow: Bool {
        behaviour.acceptsDirectManipulation && !isCollapsed
    }

    /// What a resize starting now would have to stay inside, and nil when this is not a
    /// player you may resize.
    ///
    /// Read by `PlayerWindow` at the moment of the press, for the same reason as
    /// `canDragWindow`, and gated on it: moving and resizing are the same permission, which
    /// is why refusing one has never meant allowing the other.
    ///
    /// The floor comes from `WindowSizing` rather than from `window.contentMinSize`, so the
    /// rule has one owner even though the window is told it as well. The ceiling is the same
    /// available area `apply(frameSize:animated:)` fits an oversized window into: stopping
    /// there means a resize ends where it looks like it ended, rather than growing past the
    /// screen and shrinking back on release.
    private var resizeLimits: ResizeLimits? {
        guard canDragWindow, let window, let visibleFrame = currentVisibleFrame() else {
            return nil
        }

        let minimumContent = WindowSizing.minimumContentSize(for: currentContentSize)
        return ResizeLimits(
            minimum: window.frameRect(
                forContentRect: NSRect(origin: .zero, size: minimumContent)).size,
            maximum: NSSize(
                width: visibleFrame.width - Layout.cornerMargin * 2,
                height: visibleFrame.height - Layout.cornerMargin * 2),
            anchor: corner)
    }

    /// Everything that follows from the window having just been collapsed or brought back,
    /// short of re-reading the mode. Shared by your own command and by Peek.
    private func collapseDidChange(animated: Bool) {
        applyCollapseControls()
        applyPlacement(animated: animated)
    }

    /// Judges avoidance on where the cursor is now, rather than on a disarm left over from
    /// the last dodge.
    ///
    /// Selecting a mode is a deliberate act and starts from a clean slate. Sampling here as
    /// well makes the choice land immediately: switching from Lock to Avoid leaves the
    /// tracker already running, so nothing else would look at the cursor until its next tick.
    private func rearmAvoidance() {
        avoidance.rearm()
        guard behaviour.avoidsCursor else { return }
        updateAvoidance(for: NSEvent.mouseLocation)
    }

    // MARK: - Override key

    /// Notices the override key going down and coming back up.
    ///
    /// Read from the same poll as the cursor rather than from a global event monitor, which
    /// would want the Input Monitoring permission for something the system will simply
    /// answer when asked. That poll is also the only thing that notices a release, which is
    /// why nothing stops it while the key is held.
    private func updateOverride(isHeld: Bool) {
        guard isHeld != isOverrideHeld else { return }
        isOverrideHeld = isHeld
        applyBehaviour(animated: true)

        guard !isHeld else { return }
        // Avoid is back on with the cursor almost certainly still on the window, because
        // that is what the key was held for. Treating that as an approach would run from a
        // placement just made by hand, so wait for the cursor to get clear before arming.
        avoidance.holdUntilClear()
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

        // Standing out again, and unconditionally: a reset that left the player tucked against
        // the edge would put every other setting back and leave the one thing you cannot see
        // past. `resetToDefaults` has already cleared the remembered choice, so `applyBehaviour`
        // reads back expanded.
        isCollapsed = false

        if mode != .default {
            mode = .default
            rearmAvoidance()
            onModeChange?(mode)
        }
        applyBehaviour(animated: false)

        // One animated move rather than a corner change followed by a resize: two
        // animations on the same window at the same time fight over its frame.
        corner = .default
        holdAvoidanceDuringMove()
        apply(
            contentSize: WindowSizing.resetContentSize(shapedLike: currentContentSize),
            animated: true)
    }

    // MARK: - Cursor proximity

    /// One poll, four questions. The tracker is the app's only clock, so everything that has
    /// to watch something continuously is answered from the same tick.
    ///
    /// The override key comes first: it can switch off what the others were about to do, and
    /// reading it after them would let the window move once on a tick where the user had
    /// already taken hold of it.
    private func inputSampled(at point: NSPoint) {
        updateOverride(isHeld: OverrideKey.isHeld)
        updateHoverFade(for: point)
        updateAvoidance(for: point)
        updatePeek(for: point)
    }

    /// Fade only applies to a locked player: that is when you cannot move the window
    /// out of the way by hand, so seeing through it is the only option. Holding the
    /// override key ends it, since a window you are about to take hold of should be
    /// solid enough to aim at.
    private var targetAlpha: CGFloat {
        behaviour.isClickThrough && isCursorOverWindow ? Layout.hoveredWindowAlpha : 1
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
        guard behaviour.avoidsCursor, let window else { return }

        let distance = AvoidanceResolver.distance(from: point, to: window.frame)
        guard avoidance.shouldFlee(distance: distance) else { return }

        // Asked for here rather than above the distance test, which needs only the window's
        // own frame. `NSScreen.visibleFrame` is a round trip to the window server rather than
        // a stored rectangle, so reading it up front spent that on every sample, and all but
        // one sample in a dodge is a sample where nothing happens.
        guard let visibleFrame = currentVisibleFrame() else { return }

        move(to: AvoidanceResolver.destination(
            from: corner,
            size: window.frame.size,
            cursor: point,
            visibleFrame: visibleFrame,
            margin: Layout.cornerMargin))
    }

    /// Shows whichever of the two collapse controls belongs to the state the player is in,
    /// and points its glyph the right way.
    ///
    /// Never both, and never neither by accident:
    ///
    /// - Standing out in Normal Player, the button in the corner, which is what you press to
    ///   send it away.
    /// - Collapsed, the tab, which is all of the window still on screen. Peek shows it too,
    ///   so a player the cursor tucked away looks exactly like one you collapsed yourself.
    /// - Avoid and Lock show neither. A control on a locked player would be click-through,
    ///   and one on an avoiding player would run away as you reached for it: in both cases
    ///   something that looks like it works and does not.
    private func applyCollapseControls() {
        contentView.collapseSide = collapseSide
        contentView.isCollapsed = isCollapsed
        contentView.showsCollapseTab = isCollapsed && (behaviour.canCollapse || mode.peeksFromCursor)
        contentView.showsCollapseIcon = behaviour.canCollapse && !isCollapsed
    }

    /// The screen edge this player collapses against, measured from where it stands rather
    /// than from where it is now, so it does not change while it is already tucked away.
    private var collapseSide: CollapseResolver.Side {
        guard let window, let visibleFrame = currentVisibleFrame() else { return .right }
        let standing = corner.frame(
            for: window.frame.size, in: visibleFrame, margin: Layout.cornerMargin)
        return CollapseResolver.side(for: standing, in: visibleFrame)
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

    /// Parks the window in the corner it was dragged towards.
    ///
    /// Reached from an ordinary `mouseUp`, because the drag is ours: see `WindowDragger`.
    /// While the system ran the drag, the release was swallowed by its modal loop and had to
    /// be caught by polling the button state on a timer.
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
        rememberContentSize(forFrameSize: fitted)

        let parked = corner.frame(
            for: fitted, in: visibleFrame, margin: Layout.cornerMargin)

        // A collapsed player rests off the side edge instead of in its corner. Every other
        // path in the app lands on the corner frame, so this is the single place that has to
        // know the window can be anywhere else.
        let target = isCollapsed
            ? CollapseResolver.restingFrame(
                for: parked, in: visibleFrame, tab: Layout.collapseTabWidth)
            : parked

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

    /// Writes down the size the window is about to take.
    ///
    /// Here because every path that changes the window's size arrives here, including the
    /// release that ends a hand-rolled resize, so a new way to change it cannot forget to
    /// record it.
    ///
    /// The window is told nothing about its own shape or floor. `contentAspectRatio` and
    /// `contentMinSize` only ever constrained AppKit's resize loop, which this window does
    /// not use: the shape is held by `ResizeResolver`, which takes it from the frame, and the
    /// floor comes from `WindowSizing` through `resizeLimits`. Setting them as well would be
    /// a second answer that nothing reads.
    private func rememberContentSize(forFrameSize frameSize: NSSize) {
        guard let window else { return }
        let contentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard contentSize.width > 0, contentSize.height > 0 else { return }

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

// MARK: - PlayerContentViewDelegate

extension PlayerWindowController: PlayerContentViewDelegate {
    func playerContentView(_ view: PlayerContentView, didReceiveFileAt url: URL) {
        open(url)
    }

    func playerContentViewDidClickCollapseControl(_ view: PlayerContentView) {
        toggleCollapse()
    }
}
