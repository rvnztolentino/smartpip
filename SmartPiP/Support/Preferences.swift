import Foundation

/// Settings and remembered window state, backed by `UserDefaults`.
///
/// The remembered values are written as they change rather than on quit, so a crash or a
/// Force Quit loses nothing. `UserDefaults` coalesces the writes, which matters because
/// avoid mode changes the corner every time it dodges.
@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let animatesCornerTransition = "animatesCornerTransition"
        static let corner = "lastCorner"
        static let mode = "lastMode"
        static let contentWidth = "lastContentWidth"
        static let contentHeight = "lastContentHeight"

        /// Every key this class owns, so a reset cannot miss one that is added later.
        static let all = [animatesCornerTransition, corner, mode, contentWidth, contentHeight]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.animatesCornerTransition: true])
    }

    /// `true` slides the window between corners, `false` snaps it instantly.
    var animatesCornerTransition: Bool {
        get { defaults.bool(forKey: Key.animatesCornerTransition) }
        set { defaults.set(newValue, forKey: Key.animatesCornerTransition) }
    }

    /// The corner the player was last parked in.
    ///
    /// Stored as the enum's raw string, not its index: `ScreenCorner.allCases` is
    /// ordered to describe the clockwise rotation, so reordering it is a change we
    /// should be free to make without silently repointing everyone's saved corner.
    var corner: ScreenCorner {
        get {
            defaults.string(forKey: Key.corner)
                .flatMap(ScreenCorner.init(rawValue:)) ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: Key.corner) }
    }

    /// The mode the player was last in. Unrecognised values fall back to the default,
    /// so a mode that is renamed or withdrawn later degrades to Avoid rather than
    /// refusing to launch.
    var mode: PlayerMode {
        get {
            defaults.string(forKey: Key.mode)
                .flatMap(PlayerMode.init(rawValue:)) ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// The content size the player was last left at, or `nil` if it has never been
    /// sized — a fresh install, or a plist carrying nonsense.
    ///
    /// Two scalars rather than an archived `NSSize`, so the values stay legible in
    /// `defaults read` and there is no archive format to keep compatible.
    var contentSize: NSSize? {
        get {
            let width = defaults.double(forKey: Key.contentWidth)
            let height = defaults.double(forKey: Key.contentHeight)
            guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
            return NSSize(width: width, height: height)
        }
        set {
            defaults.set(newValue?.width ?? 0, forKey: Key.contentWidth)
            defaults.set(newValue?.height ?? 0, forKey: Key.contentHeight)
        }
    }

    /// Forgets everything remembered.
    ///
    /// The keys are removed rather than overwritten with the default values, so each one
    /// comes back through the same fallback path a fresh install reads, and no default is
    /// stated twice. Anything the player still holds after a reset — its corner, its mode,
    /// its size — is written back as it re-applies it, with the same values a fresh install
    /// would have started from.
    func resetToDefaults() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
    }
}
