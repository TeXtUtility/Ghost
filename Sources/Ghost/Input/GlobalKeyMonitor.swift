import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalKeyMonitor {
    var onEvent: ((NSEvent) -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.onEvent?(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.onEvent?(event)
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor = nil }
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
