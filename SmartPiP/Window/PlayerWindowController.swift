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

    private let playback: PlaybackController
    private let contentView: PlayerContentView

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

        applyPlacement(animated: false)

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

    // MARK: - Placement

    /// Moves the window one corner clockwise.
    func cycleCorner() {
        move(to: corner.next)
    }

    func move(to corner: ScreenCorner) {
        self.corner = corner
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
