import AppKit
import CoreGraphics

// MARK: - Global Hotkey Manager
// Registers ⌃⇧S (Control + Shift + S) as a system-wide hotkey
// using a CGEvent tap — the modern, supported replacement for the
// deprecated Carbon RegisterEventHotKey API.
//
// Requires Accessibility permission (System Settings → Privacy &
// Security → Accessibility). The onboarding flow handles this.

final class HotkeyManager {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let action: () -> Void

    // The hotkey: ⌃⇧S
    private static let targetKeyCode: CGKeyCode = KeyCode.s
    private static let targetModifiers: CGEventFlags = [.maskControl, .maskShift]

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    /// Returns true if Accessibility access is granted.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user for Accessibility access (shows the system dialog).
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Checks without prompting.
    static func checkAccessibilitySilently() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func register() {
        guard eventTap == nil else { return }

        // We need a mutable pointer to self for the C callback.
        let refcon = Unmanaged.passRetained(self).toOpaque()

        // Create a tap that intercepts keyDown events system-wide.
        // .cgSessionEventTap sees events across the entire login session.
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // Can suppress events
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                // If the tap is disabled by the system (e.g. secure input),
                // re-enable it.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                // Check if the pressed key matches ⌃⇧S.
                // Mask out device-dependent bits — only check modifier keys.
                let modMask: CGEventFlags = [.maskControl, .maskShift, .maskAlternate, .maskCommand]
                let activeModifiers = flags.intersection(modMask)

                if keyCode == HotkeyManager.targetKeyCode
                    && activeModifiers == HotkeyManager.targetModifiers {
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    DispatchQueue.main.async {
                        manager.action()
                    }
                    // Suppress the event so it doesn't pass through to other apps
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )

        guard let tap = eventTap else {
            print("SnipTease: ⚠️ Failed to create event tap — Accessibility permission may be missing")
            Unmanaged<HotkeyManager>.fromOpaque(refcon).release()
            return
        }

        // Wire the tap into the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        print("SnipTease: ✅ Global hotkey ⌃⇧S registered via CGEvent tap")
    }

    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }
}

// MARK: - Key Codes
// Named constants for macOS virtual key codes, replacing magic numbers
// throughout the app. These are stable — defined by the hardware scan
// matrix and haven't changed since the original Mac keyboards.

enum KeyCode {
    static let a:         CGKeyCode = 0
    static let s:         CGKeyCode = 1
    static let d:         CGKeyCode = 2
    static let returnKey: CGKeyCode = 36
    static let tab:       CGKeyCode = 48
    static let space:     CGKeyCode = 49
    static let escape:    CGKeyCode = 53
    static let leftArrow:  CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let downArrow:  CGKeyCode = 125
    static let upArrow:    CGKeyCode = 126
}
