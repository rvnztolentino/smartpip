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

        let cycle = menu.addItem(
            withTitle: "Cycle Corner",
            action: #selector(AppDelegate.cycleCorner(_:)),
            keyEquivalent: "")
        cycle.toolTip = "Move the player to the next corner (\(HotKey.cycleCorner.displayName) anywhere)"

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Animate Corner Moves",
            action: #selector(AppDelegate.toggleAnimatedCornerTransition(_:)),
            keyEquivalent: "")

        return submenuItem(titled: "Player", menu: menu)
    }

    @MainActor
    private static func submenuItem(titled title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
