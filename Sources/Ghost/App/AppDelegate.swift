import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let library = SnippetLibrary.withSamples()
    private let state = OverlayState()
    private let picker: Picker
    private let engine: TypingEngine

    private var statusItem: StatusItemController!
    private var overlay: OverlayWindowController!
    private let keyMonitor = GlobalKeyMonitor()

    /// Snippet-library editor (the "paste big text in here" UI). Anchored to
    /// the menu bar dot.
    private let popover = NSPopover()
    private var isPopoverOpen = false

    private var overlayVisible = false

    /// Modifier triple required for picker / overlay-control shortcuts: ⌃⌥⌘.
    private static let pickerMods: NSEvent.ModifierFlags = [.control, .option, .command]

    // MARK: - Double-tap-Control state
    //
    // A "clean" tap is one where Control went down and back up quickly with
    // no other key or modifier interaction in between. Two clean taps inside
    // doubleTapMaxGap toggle the overlay (same effect as ⌃⌥⌘ H).
    private var controlPressedAt: Date?
    private var ctrlTapClean = false
    private var lastCleanCtrlTapAt: Date?
    private static let tapMaxDuration: TimeInterval = 0.25
    private static let doubleTapMaxGap: TimeInterval = 0.4

    override init() {
        self.picker = Picker(library: library)
        self.engine = TypingEngine(snippet: Snippet(name: "", body: ""))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install an Edit menu so ⌘C/V/X/A/Z route to TextField/TextEditor
        // inside the snippet-library popover.
        MainMenuInstaller.install()

        statusItem = StatusItemController()
        overlay = OverlayWindowController(
            state: state, engine: engine, picker: picker, settings: settings
        )

        statusItem.onLeftClick = { [weak self] in self?.togglePopover() }
        statusItem.onToggleOverlay = { [weak self] in self?.toggleOverlay() }
        statusItem.onQuit = { NSApp.terminate(nil) }

        keyMonitor.onEvent = { [weak self] event in self?.handleKey(event) }

        configurePopover()

        let trusted = AccessibilityPrompt.ensureTrusted(prompt: true)
        if !trusted {
            print("Ghost: Accessibility not yet granted. Grant in System Settings, then quit and relaunch.")
        }

        showOverlayInPicker()
    }

    // MARK: - Popover (snippet library)

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        let content = PopoverContentView(
            library: library,
            onActivate: { [weak self] snippet in
                self?.activateSnippet(snippet)
            },
            onClose: { [weak self] in
                self?.popover.close()
            }
        )
        let host = NSHostingController(rootView: content)
        // Explicit size so NSPopover positions correctly on first show
        // (SwiftUI's intrinsic size doesn't always propagate in time).
        host.preferredContentSize = NSSize(width: 480, height: 380)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 480, height: 380)
    }

    private func togglePopover() {
        guard let anchor = statusItem.anchorButton else { return }
        if popover.isShown {
            popover.close()
        } else {
            // .maxY = below the menu-bar dot. NSStatusBarButton uses a
            // flipped coordinate space, so .minY would aim the popover
            // upward (off the top of the screen).
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            isPopoverOpen = true
        }
    }

    private func activateSnippet(_ snippet: Snippet) {
        picker.selectByID(snippet.id)
        if !overlayVisible { showOverlayInPicker() }
        enterTypingMode()
    }

    // MARK: - Mode transitions

    private func showOverlayInPicker() {
        state.mode = .picker
        overlay.refreshLayout()
        overlay.show()
        keyMonitor.start()
        statusItem.setActive(true)
        overlayVisible = true
    }

    private func hideOverlay() {
        // Note: we DO NOT stop the keyMonitor here. Hidden is not "off"; the
        // user must still be able to press ⌃⌥⌘ H to toggle the overlay back
        // on. The monitor stays running for the lifetime of the app.
        overlay.hide()
        statusItem.setActive(false)
        overlayVisible = false
    }

    private func toggleOverlay() {
        if overlayVisible { hideOverlay() } else { showOverlayInPicker() }
    }

    private func enterTypingMode() {
        guard let snippet = picker.resolveCurrent() else { return }
        engine.reset(to: snippet)
        state.mode = .typing
        overlay.refreshLayout()
    }

    private func returnToPicker() {
        state.mode = .picker
        overlay.refreshLayout()
    }

    private func bumpFontSize(by delta: Double) {
        let next = settings.fontSize + delta
        let clamped = max(7, min(28, next))
        guard clamped != settings.fontSize else { return }
        settings.fontSize = clamped
        overlay.refreshLayout()
    }

    /// Adjust the session-only opacity override. The lower bound (0.05) is
    /// "barely visible but never fully hidden" so the user can't
    /// accidentally render the overlay completely invisible with a few
    /// keypresses and then wonder where it went.
    private func bumpSessionOpacity(by delta: Double) {
        let current = state.sessionOpacity ?? settings.opacity
        let next = current + delta
        state.sessionOpacity = max(0.05, min(1.0, next))
    }

    /// Detect a quick double-tap of the Control key (no other key pressed
    /// while it was held, two taps inside a short window) and toggle the
    /// overlay if matched. Equivalent to ⌃⌥⌘ H but reachable without a
    /// chord; useful as a thumb-only show/hide gesture.
    private func handleFlagsChangedForCtrlDoubleTap(_ event: NSEvent) {
        let mods = event.modifierFlags
        let controlIsDown = mods.contains(.control)
        let now = Date()

        if controlIsDown && controlPressedAt == nil {
            // Control just went down on its own (or as the first key of a
            // chord we'll discover next).
            controlPressedAt = now
            ctrlTapClean = true
            // If any other modifier is also already pressed, this isn't a
            // clean Control tap.
            if mods.intersection([.option, .command, .shift]) != [] {
                ctrlTapClean = false
            }
            return
        }

        if controlIsDown && controlPressedAt != nil {
            // Some other modifier pressed or released while Control is held.
            ctrlTapClean = false
            return
        }

        if !controlIsDown && controlPressedAt != nil {
            // Control just came up.
            let duration = now.timeIntervalSince(controlPressedAt!)
            controlPressedAt = nil

            guard ctrlTapClean, duration < Self.tapMaxDuration else {
                lastCleanCtrlTapAt = nil
                ctrlTapClean = false
                return
            }
            ctrlTapClean = false

            if let last = lastCleanCtrlTapAt,
               now.timeIntervalSince(last) < Self.doubleTapMaxGap {
                // Two clean taps inside the window: toggle.
                lastCleanCtrlTapAt = nil
                toggleOverlay()
            } else {
                // First clean tap; arm the second.
                lastCleanCtrlTapAt = now
            }
        }
    }

    // MARK: - Key routing

    private func handleKey(_ event: NSEvent) {
        // While the snippet-library popover is open, the user is editing
        // text inside it — don't feed any keystrokes to the typing engine
        // and don't intercept their navigation either.
        if isPopoverOpen { return }

        // Double-tap-Control gesture: detect on flagsChanged, invalidate
        // on any keyDown that happens while Control is held.
        if event.type == .flagsChanged {
            handleFlagsChangedForCtrlDoubleTap(event)
            return
        }
        if controlPressedAt != nil && event.type == .keyDown {
            // The user pressed another key while Control was down: this is
            // a chord (e.g. ⌃C, ⌃⌥⌘H), not a clean Control tap.
            ctrlTapClean = false
        }

        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == Self.pickerMods {
            let keyCode = Int(event.keyCode)

            // Always-available even when the overlay is hidden, so the user
            // can bring it back from anywhere.
            switch keyCode {
            case kVK_ANSI_H:
                // Toggle the overlay. Hidden -> shown in picker mode; visible
                // -> hidden. App stays running either way so the snippet
                // library is still reachable from the menu-bar dot.
                toggleOverlay()
                return
            case kVK_ANSI_Q:
                // Panic-quit: instantly terminate the app. Use this if you
                // want Ghost gone NOW, not just hidden.
                NSApp.terminate(nil)
                return
            default:
                break
            }

            // Everything else only makes sense when the overlay is visible.
            guard overlayVisible else { return }

            switch keyCode {
            case kVK_LeftArrow:
                switch state.mode {
                case .picker:
                    picker.prev()
                    overlay.refreshLayout()
                case .typing:
                    engine.prevWord()
                }
                return
            case kVK_RightArrow:
                switch state.mode {
                case .picker:
                    picker.next()
                    overlay.refreshLayout()
                case .typing:
                    engine.nextWord()
                }
                return
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if state.mode == .picker {
                    enterTypingMode()
                }
                return
            case kVK_Escape:
                if state.mode == .typing {
                    returnToPicker()
                } else {
                    hideOverlay()
                }
                return
            case kVK_ANSI_B:
                // Mid-typing escape hatch: bail out of the current snippet
                // and go back to the picker menu. No-op in picker mode.
                if state.mode == .typing {
                    returnToPicker()
                }
                return
            case kVK_ANSI_Equal, kVK_ANSI_KeypadPlus:
                bumpFontSize(by: +1)
                return
            case kVK_ANSI_Minus, kVK_ANSI_KeypadMinus:
                bumpFontSize(by: -1)
                return
            case kVK_ANSI_0, kVK_ANSI_Keypad0:
                overlay.snapToCorner()
                return
            case kVK_ANSI_LeftBracket:
                bumpSessionOpacity(by: -0.05)
                return
            case kVK_ANSI_RightBracket:
                bumpSessionOpacity(by: +0.05)
                return
            default:
                return
            }
        }

        // Typing-mode characters need both the overlay visible and mode=typing.
        // Hide pauses input so events don't silently advance the engine while
        // the user thinks the overlay is "off".
        guard overlayVisible, state.mode == .typing else { return }

        switch KeyEventParser.parseTyping(event) {
        case .ignore:
            return
        case .backspace:
            engine.backspace()
        case .characters(let chars):
            for ch in chars {
                engine.handle(character: ch)
                if engine.isComplete {
                    returnToPicker()
                    return
                }
            }
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.isPopoverOpen = false
        }
    }
}
