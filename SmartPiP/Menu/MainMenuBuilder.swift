import AppKit

/// Builds the app's main menu in code — the app has no nib.
///
/// Items backed by a system-wide shortcut (Cycle Corner) deliberately carry no
/// key equivalent. The Carbon hot key already consumes the combination before
/// the menu sees it, so a duplicate equivalent would only be misleading.
enum MainMenuBuilder {
    @MainActor
    static func build(appName: String) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(appName: appName))
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(playerMenuItem())
        return mainMenu
    }

    @MainActor
    private static func applicationMenuItem(appName: String) -> NSMenuItem {
        let menu = NSMenu(title: appName)
        menu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")

        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        return submenuItem(titled: appName, menu: menu)
    }

    @MainActor
    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(
            withTitle: "Open…",
            action: #selector(AppDelegate.openDocument(_:)),
            keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        return submenuItem(titled: "File", menu: menu)
    }

    @MainActor
    private static func playerMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Player")

        menu.addItem(
            withTitle: "Play/Pause",
            action: #selector(AppDelegate.togglePlayPause(_:)),
            keyEquivalent: " ")

        menu.addItem(.separator())

        // One choice with three options: exactly one is ticked, and the tick is set per
        // state in AppDelegate.validateMenuItem(_:). Built from PlayerMode.allCases, which
        // starts at Normal because that is the state the other two are departures from, and
        // which both menus read, so they cannot drift apart.
        for mode in PlayerMode.allCases {
            menu.addItem(
                withTitle: HotKey.selecting(mode).menuTitle(mode.menuTitle),
                action: Self.action(selecting: mode),
                keyEquivalent: "")
        }

        menu.addItem(overrideNote())
        menu.addItem(.separator())

        // Grouped with Cycle Corner rather than with the modes: both settle where the window
        // sits, and neither is a mode.
        menu.addItem(
            withTitle: collapseTitle,
            action: #selector(AppDelegate.toggleCollapse(_:)),
            keyEquivalent: "")

        menu.addItem(
            withTitle: HotKey.cycleCorner.menuTitle("Cycle Corner"),
            action: #selector(AppDelegate.cycleCorner(_:)),
            keyEquivalent: "")

        menu.addItem(
            withTitle: "Animate Corner Moves",
            action: #selector(AppDelegate.toggleAnimatedCornerTransition(_:)),
            keyEquivalent: "")

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Reset Settings",
            action: #selector(AppDelegate.resetSettings(_:)),
            keyEquivalent: "")

        return submenuItem(titled: "Player", menu: menu)
    }

    /// The selector that selects `mode`.
    ///
    /// Shared with `StatusItemController` so the two menus cannot drift apart, and kept as
    /// a `switch` rather than a string so a renamed action fails to compile.
    static func action(selecting mode: PlayerMode) -> Selector {
        switch mode {
        case .plain: #selector(AppDelegate.selectNormalMode(_:))
        case .lock: #selector(AppDelegate.selectLockMode(_:))
        case .peek: #selector(AppDelegate.selectPeekMode(_:))
        case .avoid: #selector(AppDelegate.selectAvoidMode(_:))
        }
    }

    /// Title of the collapse item, in both menus.
    ///
    /// One title for both directions, ticked while the player is collapsed, the same way
    /// Animate Corner Moves reads. A title that flipped to "Expand" would say what the
    /// click does but never what the player is currently doing, which is the more useful of
    /// the two when the window is a tab at the edge of the screen.
    static let collapseTitle = "Collapse to Edge"

    /// The line under the mode group explaining the hold.
    ///
    /// A note rather than a control: there is nothing to click, because the way to use it is
    /// to hold the key. It sits directly under the modes because what it says is true of
    /// every one of them.
    ///
    /// Disabled explicitly as well as having no action. Automatic enabling would settle it
    /// the same way, but only once the menu is on its way open, which leaves the item
    /// claiming to be enabled every moment before that.
    ///
    /// Shared by both menus so the wording cannot drift.
    @MainActor
    static func overrideNote() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Hold \(OverrideKey.displayName) for full control",
            action: nil,
            keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @MainActor
    private static func submenuItem(titled title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
