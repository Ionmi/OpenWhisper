import Cocoa
import Carbon.HIToolbox

final class HotkeyService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCode: UInt16
    private var modifiers: UInt32

    /// Whether the service is actively listening (recording mode is on).
    var isActive = false

    /// Current shortcut mode — set by AppState based on settings.
    var shortcutMode: Constants.ShortcutMode = .toggle

    /// Track whether the hotkey is currently held down (for Hold mode).
    private var isHotkeyHeld = false

    /// Timestamp when the hotkey was first pressed (for Auto mode).
    private var hotkeyPressTime: CFAbsoluteTime = 0

    /// Whether Auto mode resolved to toggle behavior for the current session.
    private var autoResolvedToToggle = false

    /// Threshold in seconds: press shorter than this → toggle, longer → hold.
    private let autoHoldThreshold: CFAbsoluteTime = 0.3

    var onActivate: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onEventTapFailed: (() -> Void)?
    var onEventTapCreated: (() -> Void)?

    init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func updateHotkey(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var isRunning: Bool { eventTap != nil }

    func start() {
        stop()

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if !AXIsProcessTrusted() {
                print("[HotkeyService] Failed to create event tap — Accessibility permission not granted.")
                onEventTapFailed?()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.eventTap == nil else { return }
                self.start()
            }
            return
        }
        onEventTapCreated?()

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyService] Event tap created successfully.")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        isHotkeyHeld = false
        autoResolvedToToggle = false
    }

    private func cgEventFlags(from nsModifiers: UInt32) -> CGEventFlags {
        let ns = NSEvent.ModifierFlags(rawValue: UInt(nsModifiers))
        var cg = CGEventFlags()
        if ns.contains(.shift)   { cg.insert(.maskShift) }
        if ns.contains(.control) { cg.insert(.maskControl) }
        if ns.contains(.option)  { cg.insert(.maskAlternate) }
        if ns.contains(.command) { cg.insert(.maskCommand) }
        return cg
    }

    fileprivate func handleEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if the system disabled it
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // These are not real input events, just pass through
            return Unmanaged.passRetained(event)
        }

        // If the tap was recently re-enabled, ensure it stays active
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        // Handle flagsChanged for Hold/Auto mode (detect modifier key release)
        if type == .flagsChanged {
            let isHoldBehavior = shortcutMode == .hold || (shortcutMode == .auto && !autoResolvedToToggle)
            if isHoldBehavior && isActive && isHotkeyHeld {
                let requiredFlags = cgEventFlags(from: modifiers)
                if !event.flags.contains(requiredFlags) {
                    if shortcutMode == .auto {
                        let elapsed = CFAbsoluteTimeGetCurrent() - hotkeyPressTime
                        if elapsed < autoHoldThreshold {
                            // Short press → resolve to toggle
                            autoResolvedToToggle = true
                            isHotkeyHeld = false
                            return nil
                        }
                    }
                    // Modifier released → confirm
                    isHotkeyHeld = false
                    onConfirm?()
                    return nil
                }
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passRetained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let requiredFlags = cgEventFlags(from: modifiers)
        let matchesKey = eventKeyCode == keyCode
        let matchesModifiers = event.flags.contains(requiredFlags)

        // Hold/Auto mode: detect key release of the hotkey
        let isHoldBehavior = shortcutMode == .hold || (shortcutMode == .auto && !autoResolvedToToggle)
        if isHoldBehavior && isActive && isHotkeyHeld {
            if type == .keyUp && matchesKey {
                if shortcutMode == .auto {
                    let elapsed = CFAbsoluteTimeGetCurrent() - hotkeyPressTime
                    if elapsed < autoHoldThreshold {
                        // Short press → resolve to toggle
                        autoResolvedToToggle = true
                        isHotkeyHeld = false
                        return nil
                    }
                }
                isHotkeyHeld = false
                onConfirm?()
                return nil
            }
        }

        // While active (recording): intercept ESC (both modes) and Enter (toggle only)
        if isActive {
            if type == .keyDown && eventKeyCode == UInt16(kVK_Escape) {
                isHotkeyHeld = false
                autoResolvedToToggle = false
                onCancel?()
                return nil
            }
            let isToggleBehavior = shortcutMode == .toggle || (shortcutMode == .auto && autoResolvedToToggle)
            if isToggleBehavior {
                if type == .keyDown && eventKeyCode == UInt16(kVK_Return) {
                    autoResolvedToToggle = false
                    onConfirm?()
                    return nil
                }
            }
        }

        // Check for hotkey press to activate or toggle-confirm (ignore key repeat)
        if type == .keyDown && matchesKey && matchesModifiers && !isAutoRepeat {
            if !isActive {
                isHotkeyHeld = true
                hotkeyPressTime = CFAbsoluteTimeGetCurrent()
                autoResolvedToToggle = false
                onActivate?()
            } else if shortcutMode == .toggle || (shortcutMode == .auto && autoResolvedToToggle) {
                // Pressing hotkey again while active in toggle mode → confirm
                autoResolvedToToggle = false
                onConfirm?()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleEvent(proxy, type: type, event: event)
}
