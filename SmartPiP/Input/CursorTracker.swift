import AppKit

/// Reports the global cursor position on a timer.
///
/// Polling `NSEvent.mouseLocation` is deliberate. A global event monitor would need the
/// Input Monitoring permission and would wake the app on every pointer movement;
/// sampling a few times a second costs almost nothing and needs no permission at all.
///
/// This exists because a click-through window receives no mouse events of its own — an
/// `NSTrackingArea` on a locked player never fires. Anything that has to know where the
/// pointer is while locked has to ask, rather than wait to be told.
@MainActor
final class CursorTracker {
    /// 15 Hz. Fast enough to feel immediate, slow enough to be free.
    private static let interval: TimeInterval = 1.0 / 15.0

    private let onMove: (NSPoint) -> Void
    private var timer: Timer?
    private var lastPoint: NSPoint?

    init(onMove: @escaping (NSPoint) -> Void) {
        self.onMove = onMove
    }

    deinit {
        timer?.invalidate()
    }

    var isRunning: Bool { timer != nil }

    /// Starts polling. Safe to call when already running.
    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // Generous tolerance lets the system coalesce our wake-ups with others.
        timer.tolerance = Self.interval / 3
        // Common modes, so tracking continues through menu tracking and live resize.
        RunLoop.main.add(timer, forMode: .common)

        self.timer = timer
        tick()
    }

    /// Stops polling. This is the app's only continuous idle cost, so anything that no
    /// longer needs the cursor should stop it rather than ignore the callbacks.
    func stop() {
        timer?.invalidate()
        timer = nil
        lastPoint = nil
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        guard point != lastPoint else { return }
        lastPoint = point
        onMove(point)
    }
}
