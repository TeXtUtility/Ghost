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
        keyMonitor.stop()
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

    // MARK: - Key routing

    private func handleKey(_ event: NSEvent) {
        // While the snippet-library popover is open, the user is editing
        // text inside it — don't feed any keystrokes to the typing engine
        // and don't intercept their navigation either.
        if isPopoverOpen { return }

        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == Self.pickerMods {
            switch Int(event.keyCode) {
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
            default:
                return
            }
        }

        guard state.mode == .typing else { return }

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
