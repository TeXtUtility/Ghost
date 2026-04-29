import AppKit

@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    var onLeftClick: (() -> Void)?
    var onToggleOverlay: (() -> Void)?
    var onQuit: (() -> Void)?

    /// The menu-bar button used to anchor popovers / position UI relative
    /// to the status item.
    var anchorButton: NSStatusBarButton? { item.button }

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.makeDotImage(filled: true)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func setActive(_ active: Bool) {
        item.button?.image = Self.makeDotImage(filled: active)
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            onLeftClick?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Overlay", action: #selector(toggleFromMenu), keyEquivalent: "g")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Ghost", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleFromMenu() { onToggleOverlay?() }
    @objc private func quitFromMenu() { onQuit?() }

    private static func makeDotImage(filled: Bool) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset: CGFloat = 3
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
            (filled ? NSColor.white : NSColor.white.withAlphaComponent(0.45)).setFill()
            dot.fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
