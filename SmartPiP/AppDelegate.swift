import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyCenter = HotKeyCenter()
    private var playerWindowController: PlayerWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build(appName: Self.appName)

        let controller = PlayerWindowController()
        playerWindowController = controller

        let statusItem = StatusItemController(target: self)
        statusItemController = statusItem
        controller.onModesChange = { [weak statusItem] modes in
            statusItem?.update(modes: modes)
        }

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

    @objc func toggleAvoidMode(_ sender: Any?) {
        playerWindowController?.toggle(.avoid)
    }

    @objc func toggleLockMode(_ sender: Any?) {
        playerWindowController?.toggle(.lock)
    }

    @objc func togglePlayPause(_ sender: Any?) {
        playerWindowController?.togglePlayPause()
    }

    @objc func toggleAnimatedCornerTransition(_ sender: Any?) {
        Preferences.shared.animatesCornerTransition.toggle()
    }

    // MARK: - Private

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SmartPiP"
    }

    private func registerHotKeys() {
        register(.cycleCorner) { $0.cycleCorner() }
        register(.toggleLock) { $0.toggle(.lock) }
        register(.toggleAvoid) { $0.toggle(.avoid) }
    }

    private func register(_ hotKey: HotKey, action: @escaping (PlayerWindowController) -> Void) {
        let registered = hotKeyCenter.register(hotKey) { [weak self] in
            guard let controller = self?.playerWindowController else { return }
            action(controller)
        }

        guard !registered else { return }
        NSLog(
            "SmartPiP: could not register %@ — another app may already own that shortcut.",
            hotKey.displayName)
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let modes = playerWindowController?.modes ?? .default

        switch menuItem.action {
        case #selector(toggleAnimatedCornerTransition(_:)):
            menuItem.state = Preferences.shared.animatesCornerTransition ? .on : .off
        case #selector(toggleAvoidMode(_:)):
            menuItem.state = modes.contains(.avoid) ? .on : .off
        case #selector(toggleLockMode(_:)):
            menuItem.state = modes.contains(.lock) ? .on : .off
        case #selector(togglePlayPause(_:)):
            return playerWindowController?.canTogglePlayPause ?? false
        default:
            break
        }
        return true
    }
}
