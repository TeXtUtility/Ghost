import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let panel: OverlayPanel
    private let host: NSHostingView<OverlayView>
    private let settings: Settings

    /// Default offset from the screen edge on first show. After that, the
    /// panel anchors to its current bottom-right point during resize, so
    /// dragging it elsewhere sticks.
    private let defaultEdgeOffset: CGFloat = 12

    /// Whether the panel has been positioned at least once. Drives whether
    /// the next show() snaps to the corner default or leaves it where the
    /// user dragged it.
    private var hasPositioned = false

    init(state: OverlayState, engine: TypingEngine, picker: Picker, settings: Settings) {
        self.settings = settings

        let root = OverlayView(state: state, engine: engine, picker: picker, settings: settings)
        host = NSHostingView(rootView: root)
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize

        let initialSize = NSSize(
            width: max(120, fitting.width),
            height: max(16, fitting.height)
        )
        let origin = Self.cornerOrigin(
            for: settings.corner,
            size: initialSize,
            screen: NSScreen.main,
            offset: 12
        )
        panel = OverlayPanel(contentRect: NSRect(origin: origin, size: initialSize))
        panel.contentView = host
    }

    func show() {
        if !hasPositioned {
            // First show: snap to the default corner offset.
            let fitting = currentFittingSize()
            let origin = Self.cornerOrigin(
                for: settings.corner,
                size: fitting,
                screen: NSScreen.main,
                offset: defaultEdgeOffset
            )
            panel.setFrame(NSRect(origin: origin, size: fitting), display: true)
            hasPositioned = true
        } else {
            refreshLayout()
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Re-measure the SwiftUI content and resize the panel to fit, keeping the
    /// panel's bottom-right point pinned so a size change never slides the
    /// overlay offscreen or away from where the user dragged it.
    func refreshLayout() {
        let oldFrame = panel.frame
        let bottomRight = NSPoint(x: oldFrame.maxX, y: oldFrame.minY)

        let newSize = currentFittingSize()
        let newOrigin = NSPoint(x: bottomRight.x - newSize.width, y: bottomRight.y)
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
    }

    /// Snap to the configured corner with the default edge offset.
    /// Useful as a "reset position" command if the user drags the overlay
    /// out of view.
    func snapToCorner() {
        let size = currentFittingSize()
        let origin = Self.cornerOrigin(
            for: settings.corner,
            size: size,
            screen: panel.screen ?? NSScreen.main,
            offset: defaultEdgeOffset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func currentFittingSize() -> NSSize {
        host.invalidateIntrinsicContentSize()
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        return NSSize(
            width: max(80, fitting.width),
            height: max(14, fitting.height)
        )
    }

    private static func cornerOrigin(for corner: OverlayCorner,
                                     size: NSSize,
                                     screen: NSScreen?,
                                     offset: CGFloat) -> NSPoint {
        guard let screen else { return .zero }
        // Use the full physical frame so bottom corners can sit alongside the
        // Dock rather than floating above its visibleFrame inset.
        let frame = screen.frame
        switch corner {
        case .topLeft:
            return NSPoint(x: frame.minX + offset, y: frame.maxY - size.height - offset)
        case .topRight:
            return NSPoint(x: frame.maxX - size.width - offset, y: frame.maxY - size.height - offset)
        case .bottomLeft:
            return NSPoint(x: frame.minX + offset, y: frame.minY + offset)
        case .bottomRight:
            return NSPoint(x: frame.maxX - size.width - offset, y: frame.minY + offset)
        }
    }
}
