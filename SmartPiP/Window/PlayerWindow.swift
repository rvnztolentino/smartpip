import AppKit

/// Borderless, always-on-top window that holds the player.
///
/// Position is owned by `PlayerWindowController`, which only ever parks it in a screen
/// corner. A normal player can be dragged, but only to choose which corner: it snaps to
/// the quadrant you let go in. It can also be resized from any of its edges. Whether either
/// is allowed at all depends on the mode and on where the window is, so the controller
/// decides that, and this window does the moving and the sizing.
///
/// An `NSPanel` rather than a plain window, and a non-activating one, so that clicking the
/// player never brings SmartPiP to the front.
///
/// That is what it takes to make the override key usable. macOS reserves ⌥ click on another
/// application's window for "switch to it and hide the one I am in", so every press on the
/// player with the key held was hiding whatever you were working in and revealing whatever
/// was behind it. There is no way to decline that half of the gesture: the only way out is
/// for the click not to be an app switch in the first place.
///
/// It suits the app anyway. A player that sits over your work should not take the keyboard
/// away from it just because you nudged the window. Clicks still land: the panel takes them
/// and hands them to its views exactly as before, so the transport controls, the collapse
/// controls and dragging are all unaffected.
final class PlayerWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Panels are not main windows. Left main, this would take the main menu with it while
    /// refusing to activate the app that owns the menu.
    override var canBecomeMain: Bool { false }

    /// Whether a press on draggable background should move the window right now. Asked at the
    /// moment of the press, so it is always the current mode, key and placement.
    var canDragWindow: (() -> Bool)?

    /// What a resize starting right now would have to stay inside, and nil when the player is
    /// not one you may resize. Asked at the moment of the press, for the same reason, and
    /// answering the permission and the limits together so a press cannot be allowed by one
    /// and left unbounded by the other.
    var resizeLimits: (() -> ResizeLimits?)?

    /// Called on the release that ends a drag which moved the window, so it can be parked.
    var onDragEnded: (() -> Void)?

    /// Called on the release that ends a resize which changed the window, so the new size can
    /// be re-parked and remembered.
    var onResizeEnded: (() -> Void)?

    /// What a press took hold of, decided once when it lands and then left alone.
    ///
    /// The mode, the override key and the placement can all change while a button is down,
    /// and a gesture that re-read them would be a move halfway through being a resize. One
    /// press is one gesture, from the press to the release.
    private enum Gesture {
        case moving
        case resizing
    }

    private let dragger = WindowDragger()
    private let resizer = WindowResizer()
    private var gesture: Gesture?

    /// Watches for a press on the player and moves or resizes the window itself.
    ///
    /// Intercepted here rather than in the views because the views do not reliably see it.
    /// `AVPlayerView` lays a control overlay across its whole bounds once the transport
    /// controls are on, and that overlay takes the `mouseDown` before anything underneath it
    /// does. Dragging used to survive that only because `mouseDownCanMoveWindow` is answered
    /// below the view hierarchy, by the window server. `sendEvent(_:)` is the equivalent
    /// place on our side of the fence: every event reaches it before any view gets a chance
    /// to swallow it.
    ///
    /// Which presses count is still AppKit's own rule, `mouseDownCanMoveWindow` on whichever
    /// view is hit. The picture and the black background say yes; the transport controls and
    /// the collapse controls say no, and go on taking their own clicks. Only the moving and
    /// the sizing are ours, and both have to be: the system's drag offers to tile the window
    /// against a screen edge, and this one has four legal positions.
    ///
    /// Nothing is swallowed. The events go on to their views afterwards exactly as before, so
    /// a press still brings the app forward and a click is still a click.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            gesture = beginGesture(for: event)
        case .leftMouseDragged:
            switch gesture {
            case .moving: dragger.drag(in: self)
            case .resizing: resizer.drag(in: self)
            case nil: break
            }
        case .leftMouseUp:
            endGesture()
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Reads a press as a resize, a move, or neither.
    ///
    /// The edges are checked first, because they are a band inside the same background that
    /// moves the window and the more particular of the two answers has to win. A press that
    /// is not on an edge, or on a player you may move but not resize, falls through to the
    /// drag exactly as it did before there was a resize at all.
    private func beginGesture(for event: NSEvent) -> Gesture? {
        guard let hit = contentView?.hitTest(event.locationInWindow),
              hit.mouseDownCanMoveWindow
        else { return nil }

        if let limits = resizeLimits?() {
            let edges = ResizeResolver.edges(
                at: event.locationInWindow,
                in: frame.size,
                border: Layout.resizeBorderWidth)
            if resizer.begin(in: self, edges: edges, limits: limits) { return .resizing }
        }

        guard canDragWindow?() == true, dragger.begin(in: self) else { return nil }
        return .moving
    }

    private func endGesture() {
        switch gesture {
        case .moving:
            if dragger.end() { onDragEnded?() }
        case .resizing:
            if resizer.end() { onResizeEnded?() }
        case nil:
            break
        }
        gesture = nil
    }

    init(contentRect: NSRect) {
        // `.borderless` is an empty option set, so the mask says only what this window is: a
        // panel with no chrome that never activates the app. `.nonactivatingPanel` is what
        // keeps a click on the player from bringing SmartPiP forward, and with it the ⌥ click
        // gesture that hides whatever you were in.
        //
        // Deliberately not `.resizable`. That is the switch that hands the edges to AppKit's
        // own resize loop, and on a window with no chrome the loop offers only the few points
        // it reserves at each corner: the sides were not grabbable at all. `sendEvent(_:)`
        // resizes by hand instead, from any edge, so leaving the flag in would be a second
        // mechanism racing the first for the same press.
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Panel settings come first, because they overwrite the two that matter most.
        // `isFloatingPanel` owns both `level` and `hidesOnDeactivate`, and setting it either
        // way after the fact silently undoes them: turning it off drops the level back to
        // normal and the player stops being always on top at all.
        //
        // Nothing here needs the keyboard, so the panel is asked not to take it. Now that a
        // click no longer activates the app, being the key window would mean holding focus
        // for an app that is not even in front.
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // A floating panel hides itself whenever its app is not in front. For a player that
        // is meant to sit over your work while you use something else, that is the one thing
        // it must never do.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .black
        preventsApplicationTerminationWhenModal = false

        // The system never moves or resizes this window, in any mode. Its drag loop offers to
        // tile a window that reaches a screen edge, drawing an outline and then resizing the
        // player to half the display, and this one has exactly four legal positions. Both
        // gestures still work: `sendEvent(_:)` above does them by hand.
        //
        // Both flags, because they are different routes to the same loop: `isMovable` covers
        // a drag the window server starts on its own, including the ⌃⌘ drag-from-anywhere
        // gesture, and `isMovableByWindowBackground` covers one started from a view that
        // answers `mouseDownCanMoveWindow`. That property is still read, but only by us, and
        // only as the question it names: may a press here move the window.
        isMovable = false
        isMovableByWindowBackground = false

        // Size limits and the aspect lock are not set here: both depend on the shape of
        // whatever is playing, so `PlayerWindowController` owns them and updates them
        // together. Setting a floor here as well would just be a second answer to the
        // same question.
    }
}
