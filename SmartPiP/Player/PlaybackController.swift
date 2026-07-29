import AVFoundation
import AVKit
import AppKit

/// Owns the `AVPlayer` and the `AVPlayerView` that hosts it.
///
/// `AVPlayerView` gives us the native transport controls and hardware decode via
/// VideoToolbox for free, so this type stays thin: load a URL, start playing,
/// and report the video's presentation size so the window can resize to match.
@MainActor
final class PlaybackController {
    let playerView: AVPlayerView

    private(set) var currentURL: URL?

    init() {
        playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.updatesNowPlayingInfoCenter = false
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
