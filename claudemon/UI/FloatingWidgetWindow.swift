import AppKit
import SwiftUI

final class FloatingWidgetWindow: NSPanel, NSWindowDelegate {
    private static let cornerSnapThreshold: CGFloat = 40

    init(usageStore: UsageStore) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        delegate = self

        let hostingView = NSHostingView(rootView: FloatingWidgetView(usageStore: usageStore))
        contentView = hostingView
        // The view's row structure never changes shape (placeholders fill in
        // for missing data instead of removing rows), so this fitting size is
        // the final size for the panel's whole lifetime — no later resize to
        // fight with while anchoring the top-left corner.
        setContentSize(hostingView.fittingSize)
        positionTopLeft()
    }

    func positionTopLeft(margin: CGFloat = 12) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.minX + margin,
            y: visible.maxY - frame.height - margin
        )
        setFrameOrigin(origin)
    }

    /// Called by AppKit while the window is being dragged (via
    /// `isMovableByWindowBackground`) and on any programmatic frame change,
    /// keeping the panel fully on-screen without the user having to notice
    /// any clamping.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? self.screen ?? NSScreen.main else { return frameRect }
        let visible = screen.visibleFrame
        var rect = frameRect
        rect.origin.x = min(max(rect.origin.x, visible.minX), visible.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, visible.minY), visible.maxY - rect.height)
        return rect
    }

    /// `windowDidMove` fires repeatedly while dragging; checking for a
    /// released mouse button is how we tell a live drag update apart from
    /// the final position once the user lets go, without a dedicated
    /// "drag ended" delegate method.
    func windowDidMove(_ notification: Notification) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        snapToNearestCornerIfClose()
    }

    private func snapToNearestCornerIfClose() {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size

        let corners = [
            NSPoint(x: visible.minX, y: visible.maxY - size.height),
            NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height),
            NSPoint(x: visible.minX, y: visible.minY),
            NSPoint(x: visible.maxX - size.width, y: visible.minY)
        ]

        guard let nearest = corners.min(by: { distance($0, frame.origin) < distance($1, frame.origin) }),
              distance(nearest, frame.origin) <= Self.cornerSnapThreshold else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(nearest)
        }
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
