import AppKit
import SwiftUI

final class FloatingWidgetWindow: NSPanel, NSWindowDelegate {
    private static let cornerSnapThreshold: CGFloat = 40

    private let provider: UsageProvider
    private var isSnapping = false

    init(providerStore: ProviderUsageStore, stackIndex: Int) {
        provider = providerStore.provider

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

        let hostingView = NSHostingView(rootView: FloatingWidgetView(providerStore: providerStore))
        contentView = hostingView
        setContentSize(hostingView.fittingSize)

        if let savedOrigin = Self.loadSavedOrigin(for: provider) {
            setFrame(constrainFrameRect(NSRect(origin: savedOrigin, size: frame.size), to: screen ?? NSScreen.main), display: false)
        } else {
            positionTopLeft(stackIndex: stackIndex)
        }
    }

    func positionTopLeft(stackIndex: Int, margin: CGFloat = 12, spacing: CGFloat = 10) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.minX + margin,
            y: visible.maxY - frame.height - margin - CGFloat(stackIndex) * (frame.height + spacing)
        )
        setFrameOrigin(origin)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? self.screen ?? NSScreen.main else { return frameRect }
        let visible = screen.visibleFrame
        var rect = frameRect
        rect.origin.x = min(max(rect.origin.x, visible.minX), visible.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, visible.minY), visible.maxY - rect.height)
        return rect
    }

    func windowDidMove(_ notification: Notification) {
        guard NSEvent.pressedMouseButtons == 0, !isSnapping else { return }
        if !snapToNearestCornerIfClose() {
            Self.saveOrigin(frame.origin, for: provider)
        }
    }

    @discardableResult
    private func snapToNearestCornerIfClose() -> Bool {
        guard let screen = screen ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame
        let size = frame.size

        let corners = [
            NSPoint(x: visible.minX, y: visible.maxY - size.height),
            NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height),
            NSPoint(x: visible.minX, y: visible.minY),
            NSPoint(x: visible.maxX - size.width, y: visible.minY)
        ]

        guard let nearest = corners.min(by: { distance($0, frame.origin) < distance($1, frame.origin) }),
              distance(nearest, frame.origin) <= Self.cornerSnapThreshold else { return false }

        isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(nearest)
        } completionHandler: { [weak self] in
            guard let self else { return }
            isSnapping = false
            Self.saveOrigin(frame.origin, for: provider)
        }
        return true
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func originDefaultsKey(for provider: UsageProvider) -> String {
        "floatingWidgetOrigin.\(provider.rawValue)"
    }

    private static func saveOrigin(_ origin: NSPoint, for provider: UsageProvider) {
        UserDefaults.standard.set([origin.x, origin.y], forKey: originDefaultsKey(for: provider))
    }

    private static func loadSavedOrigin(for provider: UsageProvider) -> NSPoint? {
        guard let coordinates = UserDefaults.standard.array(forKey: originDefaultsKey(for: provider)) as? [Double],
              coordinates.count == 2 else { return nil }
        return NSPoint(x: coordinates[0], y: coordinates[1])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
