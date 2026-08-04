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

        let statusItem = StatusItemController(target: self, mode: controller.mode)
        statusItemController = statusItem
        controller.onModeChange = { [weak statusItem] mode in
            statusItem?.update(mode: mode)
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        registerHotKeys()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyCenter.unregisterAll()
    }

    /// No. The player is a panel, and AppKit does not count panels here.
    ///
    /// This used to answer yes, back when the player was an ordinary window and closing it
    /// was the only way to reach zero windows. Now that it is an `NSPanel`, AppKit leaves it
    /// out of the count, so the app looks like it has no windows at all times and this is
    /// asked every time any window anywhere in the app closes. A menu is a window: opening
    /// the menu bar item and picking anything from it closed the menu, tripped the check, and
    /// quit the app.
    ///
    /// Nothing is lost by answering no. The player has no close button and cannot be closed:
    /// its style mask has no `.closable`, so Close in the File menu is greyed out, ⌘W beeps,
    /// and Escape, which panels otherwise treat as a close, does nothing either. There is no
    /// way to be left running with no player, which is the state this was guarding against.
    /// Quit is still Quit, in both menus.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu actions

    @objc func openDocument(_ sender: Any?) {
        playerWindowController?.presentOpenPanel()
    }

    @objc func cycleCorner(_ sender: Any?) {
        playerWindowController?.cycleCorner()
    }

    @objc func selectNormalMode(_ sender: Any?) {
        playerWindowController?.setMode(.plain)
    }

    @objc func selectAvoidMode(_ sender: Any?) {
        playerWindowController?.setMode(.avoid)
    }

    @objc func selectLockMode(_ sender: Any?) {
        playerWindowController?.setMode(.lock)
    }

    @objc func selectPeekMode(_ sender: Any?) {
        playerWindowController?.setMode(.peek)
    }

    @objc func toggleCollapse(_ sender: Any?) {
        playerWindowController?.toggleCollapse()
    }

    @objc func togglePlayPause(_ sender: Any?) {
        playerWindowController?.togglePlayPause()
    }

    @objc func toggleAnimatedCornerTransition(_ sender: Any?) {
        Preferences.shared.animatesCornerTransition.toggle()
    }

    @objc func resetSettings(_ sender: Any?) {
        playerWindowController?.resetSettings()
    }

    // MARK: - Private

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SmartPiP"
    }

    private func registerHotKeys() {
        register(.cycleCorner) { $0.cycleCorner() }
        for mode in PlayerMode.allCases {
            register(.selecting(mode)) { $0.setMode(mode) }
        }
    }

    private func register(_ hotKey: HotKey, action: @escaping (PlayerWindowController) -> Void) {
        let registered = hotKeyCenter.register(hotKey) { [weak self] in
            guard let controller = self?.playerWindowController else { return }
            action(controller)
        }

        guard !registered else { return }
        NSLog(
            "SmartPiP: could not register %@. Another app may already own that shortcut.",
            hotKey.displayName)
    }
}

// MARK: - NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let mode = playerWindowController?.mode ?? .default

        // Exactly one of the mode items is ticked at all times. The item for the current
        // mode stays enabled: selecting it is a no-op rather than an error, and greying it
        // out would make the group look broken.
        switch menuItem.action {
        case #selector(toggleAnimatedCornerTransition(_:)):
            menuItem.state = Preferences.shared.animatesCornerTransition ? .on : .off
        case #selector(selectNormalMode(_:)):
            menuItem.state = mode == .plain ? .on : .off
        case #selector(selectAvoidMode(_:)):
            menuItem.state = mode == .avoid ? .on : .off
        case #selector(selectLockMode(_:)):
            menuItem.state = mode == .lock ? .on : .off
        case #selector(selectPeekMode(_:)):
            menuItem.state = mode == .peek ? .on : .off
        case #selector(togglePlayPause(_:)):
            return playerWindowController?.canTogglePlayPause ?? false
        case #selector(toggleCollapse(_:)):
            // Greyed out rather than hidden outside Normal Player. Unlike the mode group,
            // where greying the ticked item would look broken, this one genuinely is not
            // available, and saying so is more use than removing the line people are
            // looking for.
            menuItem.state = playerWindowController?.isCollapsed == true ? .on : .off
            return playerWindowController?.canToggleCollapse ?? false
        default:
            break
        }
        return true
    }
}
