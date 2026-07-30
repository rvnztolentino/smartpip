import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
struct HotKey {
    /// Unique within SmartPiP; identifies the shortcut in the Carbon callback.
    let identifier: UInt32
    /// Virtual key code, e.g. `kVK_ANSI_C`.
    let keyCode: UInt32
    /// Carbon modifier mask, e.g. `cmdKey | optionKey`.
    let modifiers: UInt32
    /// Human-readable form, for menus and documentation.
    let displayName: String
}

extension HotKey {
    static let cycleCorner = HotKey(
        identifier: 1,
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘C"
    )

    static let selectLock = HotKey(
        identifier: 2,
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘L"
    )

    static let selectAvoid = HotKey(
        identifier: 3,
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘A"
    )

    /// The way out of both other modes, and the primary control in lock mode: with the
    /// window click-through, this is the only route back that does not need the pointer.
    ///
    /// It exists because selecting a mode no longer toggles it off. Without a shortcut of
    /// its own, a locked player could only be released through the menu bar.
    static let selectNormal = HotKey(
        identifier: 4,
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        displayName: "⌃⌥⌘N"
    )

    /// The shortcut for `mode`, so the menus and the registration table cannot disagree
    /// about which key selects which mode.
    static func selecting(_ mode: PlayerMode) -> HotKey {
        switch mode {
        case .plain: .selectNormal
        case .avoid: .selectAvoid
        case .lock: .selectLock
        }
    }

    /// Menu title with the shortcut appended.
    ///
    /// Menu items backed by a hot key deliberately carry no `keyEquivalent`. The
    /// Carbon hot key consumes the combination before the menu system sees it, and
    /// binding it in both places risks the action running twice — which for a mode
    /// selection would be invisible, and for the old toggles looked like nothing
    /// happening at all. Putting the shortcut in the title keeps it discoverable
    /// without that risk.
    func menuTitle(_ base: String) -> String {
        "\(base)  \(displayName)"
    }
}

/// Registers system-wide shortcuts using Carbon's `RegisterEventHotKey`.
///
/// Carbon hot keys are used rather than `NSEvent.addGlobalMonitorForEvents`
/// because they work without the Accessibility / Input Monitoring permission
/// prompt, and they only wake the app for the exact combinations we asked for.
@MainActor
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    deinit {
        // `registrations` and `eventHandler` are plain C handles; releasing them
        // here keeps the Carbon side balanced even if `unregisterAll` was missed.
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers `hotKey`, replacing any previous registration with the same
    /// identifier. Returns `false` if the system refused it, which usually means
    /// another application already owns the combination.
    @discardableResult
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregister(hotKey)

        let hotKeyID = EventHotKeyID(signature: smartPiPHotKeySignature, id: hotKey.identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }

        registrations[hotKey.identifier] = reference
        handlers[hotKey.identifier] = handler
        return true
    }

    func unregister(_ hotKey: HotKey) {
        if let reference = registrations.removeValue(forKey: hotKey.identifier) {
            UnregisterEventHotKey(reference)
        }
        handlers[hotKey.identifier] = nil
    }

    func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        handlers.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handle(identifier: UInt32) {
        handlers[identifier]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            smartPiPHotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

/// Four-character code identifying SmartPiP's hot keys ('SPiP').
private let smartPiPHotKeySignature: OSType = 0x5350_6950

/// Carbon calls this on the main thread from the app's event dispatcher.
private func smartPiPHotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr, hotKeyID.signature == smartPiPHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        center.handle(identifier: hotKeyID.id)
    }
    return noErr
}
