@preconcurrency import AppKit
import Carbon.HIToolbox
@preconcurrency import CoreGraphics

@MainActor
final class GlobalKeyMonitor {
    /// Returns true if the event was consumed (suppress system delivery).
    /// Returning false lets the keystroke reach the focused app normally.
    var onEvent: ((NSEvent) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: GlobalKeyMonitor.tapCallback,
            userInfo: userInfo
        ) else {
            // Tap creation fails without Accessibility — the prompt at launch
            // covers this, but if the user denied we silently no-op rather
            // than crash. They'll see the overlay but it won't react.
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        // The system disables our tap if it takes too long or under certain
        // user-input conditions. Re-enable so the next keystroke works.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let consumed = MainActor.assumeIsolated { () -> Bool in
            guard let nsEvent = NSEvent(cgEvent: event) else { return false }
            return monitor.onEvent?(nsEvent) ?? false
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}

/// Parsed typing input derived from a key event. Used by the typing-mode
/// router; picker-mode hotkeys are handled separately by keyCode + modifiers.
enum TypingInput {
    case characters([Character])
    case backspace
    case ignore
}

@MainActor
enum KeyEventParser {
    static func parseTyping(_ event: NSEvent) -> TypingInput {
        let mods = event.modifierFlags

        // Anything with Command/Control is a shortcut — not typing.
        if mods.contains(.command) || mods.contains(.control) { return .ignore }

        if event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete {
            return .backspace
        }
        if event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            return .characters(["\n"])
        }
        if event.keyCode == kVK_Tab {
            return .characters(["\t"])
        }

        guard let chars = event.characters, !chars.isEmpty else { return .ignore }
        let kept = chars.filter(isTypingRelevant)
        return kept.isEmpty ? .ignore : .characters(Array(kept))
    }

    /// Filter out non-typing characters: arrow keys, function keys, and other
    /// AppKit "special" keys live in Unicode private-use area 0xF700–0xF8FF.
    /// Also drop ASCII control codes that aren't \n or \t.
    static func isTypingRelevant(_ ch: Character) -> Bool {
        for scalar in ch.unicodeScalars {
            if (0xF700...0xF8FF).contains(scalar.value) { return false }
        }
        if ch == "\n" || ch == "\t" { return true }
        if let a = ch.asciiValue, a < 0x20 || a == 0x7F { return false }
        return true
    }
}
