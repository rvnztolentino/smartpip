import Foundation

/// Decides *whether* the window should run, where `AvoidanceResolver` decides where.
///
/// This is a state machine over a stream of cursor distances, so it lives apart from
/// the controller: fed a sequence of distances it can be checked outright, which is
/// the only honest way to test a rule about a moving pointer.
struct AvoidanceTrigger {
    /// False between a dodge and the cursor getting clear of the window again.
    private var isArmed = true

    /// When the window stops sliding. Nil when nothing is in flight.
    private var settlesAt: Date?

    /// Whether the window should run now, given how far the cursor is from it.
    ///
    /// Fed every sample, not just the ones where the cursor moved: the distance
    /// changes when the window moves too, and the disarm is only lifted by seeing
    /// the window land somewhere clear.
    ///
    /// Two things stop one dodge turning into a chase:
    ///
    /// - The trigger and release distances differ. After running, the window has to
    ///   see the cursor well clear before it will run again — otherwise a pointer
    ///   parked on the boundary would pump it between corners. `AvoidanceResolver`
    ///   only ever lands it beyond the release distance, so in practice the next
    ///   sample after a dodge re-arms it; the gap earns its keep on a screen too
    ///   small to get clear, where the window stays put instead of hopping forever.
    /// - Nothing counts while the window is still sliding. It sweeps across the
    ///   screen and can pass the pointer on the way, which is not an approach.
    mutating func shouldFlee(distance: CGFloat, now: Date = Date()) -> Bool {
        if let settlesAt {
            guard now >= settlesAt else { return false }
            self.settlesAt = nil
        }

        guard isArmed else {
            if distance >= Layout.avoidReleaseDistance { isArmed = true }
            return false
        }

        guard distance <= Layout.avoidTriggerDistance else { return false }
        isArmed = false
        return true
    }

    /// Call when the window starts an animated move, dodge or otherwise.
    mutating func windowIsMoving(until date: Date) {
        settlesAt = date
    }

    /// Call whenever the mode changes. Switching Avoid on is a deliberate act and
    /// should be judged on where the cursor is now, not on a disarm left over from
    /// the last time the window ran.
    mutating func rearm() {
        isArmed = true
        settlesAt = nil
    }
}
