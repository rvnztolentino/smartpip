import Foundation

/// User-visible settings, backed by `UserDefaults`.
@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let animatesCornerTransition = "animatesCornerTransition"
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
}
