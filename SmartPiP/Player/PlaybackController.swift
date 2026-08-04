import AVFoundation
import AVKit
import AppKit

/// An `AVPlayerView` that lets a drag on the picture move the window.
///
/// The video fills the whole window, so without this there is nothing left to drag by.
private final class DraggableVideoView: AVPlayerView {
    /// Says the picture is background you may drag the window by. `PlayerWindow.sendEvent`
    /// reads it and does the moving; the system is never asked, because its drag offers to
    /// tile the window against a screen edge.
    ///
    /// The transport controls are separate subviews and answer no, so they go on taking
    /// their own clicks: you drag the picture and click the buttons. Whether dragging is
    /// allowed at all is the controller's business, so this needs to know nothing about
    /// modes itself.
    override var mouseDownCanMoveWindow: Bool { true }

    /// The player floats above everything and is rarely the frontmost app, so without this
    /// the first click would be spent activating SmartPiP.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the `AVPlayer` and the `AVPlayerView` that hosts it.
///
/// `AVPlayerView` gives us the native transport controls and hardware decode via
/// VideoToolbox for free, so this type stays thin: load a URL, start playing,
/// and report the video's presentation size so the window can resize to match.
@MainActor
final class PlaybackController {
    let playerView: AVPlayerView

    private(set) var currentURL: URL?

    /// `controlsVisible` comes from the restored mode rather than being assumed here, so
    /// a player that relaunches into a mode without controls never shows a frame of them.
    init(controlsVisible: Bool) {
        playerView = DraggableVideoView()
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.updatesNowPlayingInfoCenter = false
        setControlsVisible(controlsVisible)
    }

    /// `.none` removes the transport controls outright, so nothing fades in when the
    /// pointer crosses the window. Play/pause stays reachable from the menus.
    ///
    /// The guard is not just an optimisation. Every mode change and every press or release of
    /// the override key comes through here, and most of them ask for the style it is already
    /// in; doing the work anyway would tear the controls down and build them up again several
    /// times a second while the cursor moves.
    func setControlsVisible(_ visible: Bool) {
        let style: AVPlayerViewControlsStyle = visible ? .floating : .none
        guard playerView.controlsStyle != style else { return }

        playerView.controlsStyle = style
        setControlChromeHidden(!visible)
    }

    /// Takes down the controls' backdrop when they are switched off mid-hover.
    ///
    /// `AVPlayerView` builds its floating controls inside a container of its own and fades
    /// that container in and out with the pointer. Setting `controlsStyle` to `.none` removes
    /// the buttons but leaves the container exactly as it was, so a style change made while
    /// the controls are showing strands the blurred grey panel behind them, at full opacity,
    /// over the picture. Nothing afterwards takes it away: the pointer leaving does not, since
    /// AVKit is no longer managing it, and neither does a re-layout, a detour through another
    /// style, detaching the player, or removing and re-adding the whole view.
    ///
    /// That is exactly what holding the override key does. The key goes down, the controls
    /// become available, you hover, and the moment you let go the style changes underneath a
    /// visible control bar.
    ///
    /// Found by walking the view tree, so it depends on AVKit's own class name. If that name
    /// ever changes this quietly does nothing and the panel comes back, which is the same
    /// behaviour as not having the workaround at all: it cannot break anything by failing.
    /// Nothing is destroyed either, only hidden, and it is shown again the moment the
    /// controls are wanted, so AVKit gets its container back in the state it left it.
    private func setControlChromeHidden(_ hidden: Bool) {
        Self.controlChrome(in: playerView)?.isHidden = hidden
    }

    private static func controlChrome(in view: NSView) -> NSView? {
        if String(describing: type(of: view)) == "AVEventPassthroughView" { return view }
        for subview in view.subviews {
            if let found = controlChrome(in: subview) { return found }
        }
        return nil
    }

    var isPlaying: Bool {
        playerView.player?.timeControlStatus == .playing
    }

    var hasVideo: Bool {
        playerView.player?.currentItem != nil
    }

    func togglePlayPause() {
        guard let player = playerView.player, player.currentItem != nil else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    /// Loads `url` and begins playback.
    ///
    /// Returns the video's presentation size (natural size with its preferred
    /// transform applied, so rotated footage reports the size you actually see),
    /// or `nil` if the file carries no usable video track.
    @discardableResult
    func load(_ url: URL) async -> NSSize? {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        if let player = playerView.player {
            player.replaceCurrentItem(with: item)
        } else {
            playerView.player = AVPlayer(playerItem: item)
        }

        currentURL = url
        playerView.player?.play()

        return await Self.presentationSize(of: asset)
    }

    private static func presentationSize(of asset: AVURLAsset) async -> NSSize? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let transformed = naturalSize.applying(transform)
            let size = NSSize(width: abs(transformed.width), height: abs(transformed.height))
            guard size.width > 0, size.height > 0 else { return nil }
            return size
        } catch {
            return nil
        }
    }
}
