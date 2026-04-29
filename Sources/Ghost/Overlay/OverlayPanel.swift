import AppKit

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Accept clicks so the user can drag the overlay to reposition it.
        // The .nonactivatingPanel style + canBecomeKey/Main = false ensure
        // clicking it never steals focus from the user's real document.
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        worksWhenModal = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}
