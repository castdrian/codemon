import AppKit
import SwiftUI
import Combine
import AppUpdater
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private lazy var usageStore = UsageStore()
    private var floatingWindows: [UsageProvider: FloatingWidgetWindow] = [:]
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let appUpdater = AppUpdater(owner: "castdrian", repo: "codemon")
    private var appActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "codemon")
        buildMenu()

        usageStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        appUpdater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleUpdaterState(state) }
            .store(in: &cancellables)

        updateFloatingWidgetVisibility()

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateFloatingWidgetVisibility()
        }

        SettingsStore.shared.$showWidgetOnlyWhenProviderFocused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFloatingWidgetVisibility() }
            .store(in: &cancellables)

        KeyboardShortcuts.onKeyUp(for: .toggleWidget) { [weak self] in
            self?.toggleFloatingWidget()
        }

        #if DEBUG
        appUpdater.skipCodeSignValidation = true
        #else
        appUpdater.check()
        #endif
    }

    private func buildMenu() {
        let menu = NSMenu()

        for providerStore in usageStore.providerStores {
            let name = providerStore.provider.displayName
            if let snapshot = providerStore.snapshot {
                if let session = snapshot.session {
                    menu.addItem(withTitle: "\(name) Session: \(Int(session.utilization.rounded()))%", action: nil, keyEquivalent: "")
                }
                if let weekly = snapshot.weekly {
                    menu.addItem(withTitle: "\(name) Weekly: \(Int(weekly.utilization.rounded()))%", action: nil, keyEquivalent: "")
                }
                if let percent = snapshot.credit?.percentUsed {
                    menu.addItem(withTitle: "\(name) Credits: \(Int(percent.rounded()))%", action: nil, keyEquivalent: "")
                }
            } else if let error = providerStore.lastError {
                menu.addItem(withTitle: "\(name): \(error)", action: nil, keyEquivalent: "")
            }
        }

        if !usageStore.providerStores.allSatisfy({ $0.snapshot == nil }) {
            menu.addItem(.separator())
        }

        menu.addItem(Self.item("Refresh Now", symbol: "arrow.clockwise", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        let widgetItem = Self.item("Show Floating Widget", symbol: "rectangle.inset.filled", action: #selector(toggleFloatingWidget))
        widgetItem.state = SettingsStore.shared.showFloatingWidget ? .on : .off
        menu.addItem(widgetItem)
        menu.addItem(Self.item("Settings…", symbol: "gearshape", action: #selector(openSettings)))
        menu.addItem(Self.item("Check for Updates…", symbol: "arrow.down.circle", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(Self.item("Support codemon on Ko-fi…", symbol: "cup.and.saucer", action: #selector(openKofi)))
        menu.addItem(.separator())
        menu.addItem(Self.item("Quit codemon", symbol: "power", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private static func item(_ title: String, symbol: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    @objc private func refreshNow() {
        Task { await usageStore.refresh() }
    }

    @objc private func toggleFloatingWidget() {
        SettingsStore.shared.showFloatingWidget.toggle()
        updateFloatingWidgetVisibility()
        buildMenu()
    }

    private func updateFloatingWidgetVisibility() {
        guard SettingsStore.shared.showFloatingWidget else {
            floatingWindows.values.forEach { $0.orderOut(nil) }
            return
        }

        let activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for (index, providerStore) in usageStore.providerStores.enumerated() {
            let isVisible: Bool
            if SettingsStore.shared.showWidgetOnlyWhenProviderFocused {
                isVisible = activeBundleIdentifier.map { providerStore.provider.desktopBundleIdentifiers.contains($0) } ?? false
            } else {
                isVisible = true
            }
            setWidgetWindowVisible(isVisible, for: providerStore, stackIndex: index)
        }
    }

    private func setWidgetWindowVisible(_ visible: Bool, for providerStore: ProviderUsageStore, stackIndex: Int) {
        guard visible else {
            floatingWindows[providerStore.provider]?.orderOut(nil)
            return
        }
        let window: FloatingWidgetWindow
        if let existing = floatingWindows[providerStore.provider] {
            window = existing
        } else {
            window = FloatingWidgetWindow(providerStore: providerStore, stackIndex: stackIndex)
            floatingWindows[providerStore.provider] = window
        }
        window.orderFrontRegardless()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let hosting = NSHostingController(rootView: SettingsView(usageStore: usageStore))
            let window = NSWindow(contentViewController: hosting)
            window.title = "codemon settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openKofi() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/castdrian")!)
    }

    @objc private func checkForUpdates() {
        appUpdater.check()
    }

    private func handleUpdaterState(_ state: AppUpdater.UpdateState) {
        guard case .downloaded(let release, _, let bundle) = state else { return }
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "codemon \(release.tagName) is ready to install."
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { appUpdater.install(bundle) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
