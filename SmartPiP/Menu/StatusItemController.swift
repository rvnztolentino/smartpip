import AppKit

/// The menu bar item.
///
/// This is not a convenience. In lock mode the window is click-through, so it can no
/// longer be clicked to bring SmartPiP forward — the menu bar item is then the only
/// pointer-driven control left, and the way back for anyone who has not memorised the
/// unlock shortcut.
///
/// Items target the app delegate explicitly rather than travelling the responder
/// chain, because a status item menu is opened while another app is frontmost.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private weak var target: AppDelegate?

    init(target: AppDelegate) {
        self.target = target
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = Self.makeMenu(target: target)
        update(mode: .default)
    }

    /// Reflects the current mode in the menu bar icon.
    func update(mode: PlayerMode) {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: mode.statusSymbolName,
            accessibilityDescription: mode.statusDescription)
        image?.isTemplate = true
        button.image = image
        button.toolTip = mode.statusDescription
    }

    private static func makeMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu()

        add(to: menu, title: "Open…", action: #selector(AppDelegate.openDocument(_:)), target: target)
        add(to: menu, title: "Play/Pause",
            action: #selector(AppDelegate.togglePlayPause(_:)), target: target)
        menu.addItem(.separator())

        // Checkmarks are set per state in AppDelegate.validateMenuItem(_:).
        add(to: menu, title: HotKey.toggleAvoid.menuTitle("Avoid Cursor"),
            action: #selector(AppDelegate.toggleAvoidMode(_:)), target: target)
        add(to: menu, title: HotKey.toggleLock.menuTitle("Lock Player"),
            action: #selector(AppDelegate.toggleLockMode(_:)), target: target)
        menu.addItem(.separator())

        add(to: menu, title: HotKey.cycleCorner.menuTitle("Cycle Corner"),
            action: #selector(AppDelegate.cycleCorner(_:)), target: target)
        add(to: menu, title: "Animate Corner Moves",
            action: #selector(AppDelegate.toggleAnimatedCornerTransition(_:)), target: target)
        menu.addItem(.separator())

        add(to: menu, title: "Quit SmartPiP",
            action: #selector(NSApplication.terminate(_:)), target: NSApp)

        return menu
    }

    @discardableResult
    private static func add(
        to menu: NSMenu, title: String, action: Selector, target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        return item
    }
}
