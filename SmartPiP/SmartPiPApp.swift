import AppKit

/// Entry point. The app has no nib, so it wires up `NSApplication` by hand.
@main
enum SmartPiPApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}
