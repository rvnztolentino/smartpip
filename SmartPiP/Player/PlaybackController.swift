import AVFoundation
import AVKit
import AppKit

/// An `AVPlayerView` that lets a drag on the picture move the window.
///
/// The video fills the whole window, so without this there is nothing left to drag by.
/// Two mechanisms, because they cover different paths and neither is guaranteed on its own:
/// `mouseDownCanMoveWindow` is what AppKit consults for `isMovableByWindowBackground`, and
/// `performDrag(with:)` starts the same drag explicitly if the event reaches us instead.
/// Whichever runs, the window moves once and `windowDidMove` arms the snap.
///
/// The transport controls are separate subviews, so they are hit first and keep taking
/// their own clicks: you drag the picture and click the buttons. `isMovable` is false in
/// the other two modes, which is what stops a drag there, so this needs to know nothing
/// about modes itself.
private final class DraggableVideoView: AVPlayerView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window, window.isMovable else {
            super.mouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }
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
    /// a player that relaunches into Avoid or Lock never shows a frame of controls first.
    init(controlsVisible: Bool) {
        playerView = DraggableVideoView()
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.updatesNowPlayingInfoCenter = false
        setControlsVisible(controlsVisible)
    }

    /// `.none` removes the transport controls outright, so nothing fades in when the
    /// pointer crosses the window. Play/pause stays reachable from the menus.
    func setControlsVisible(_ visible: Bool) {
        playerView.controlsStyle = visible ? .floating : .none
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
