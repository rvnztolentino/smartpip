import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyCenter = HotKeyCenter()
    private var playerWindowController: PlayerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(appName: Self.appName)

        let controller = PlayerWindowController()
        playerWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        registerHotKeys()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu actions

    @objc func openDocument(_ sender: Any?) {
        playerWindowController?.presentOpenPanel()
    }

    @objc func cycleCorner(_ sender: Any?) {
        playerWindowController?.cycleCorner()
    }

    @objc func toggleAnimatedCornerTransition(_ sender: Any?) {
        Preferences.shared.animatesCornerTransition.toggle()
    }

    // MARK: - Private

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SmartPiP"
    }

    private func registerHotKeys() {
        let registered = hotKeyCenter.register(.cycleCorner) { [weak self] in
            self?.playerWindowController?.cycleCorner()
        }

        if !registered {
            NSLog(
                "SmartPiP: could not register %@ — another app may already own that shortcut.",
                HotKey.cycleCorner.displayName)
        }
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAnimatedCornerTransition(_:)) {
            menuItem.state = Preferences.shared.animatesCornerTransition ? .on : .off
        }
        return true
    }
}
