import AppKit
import SwiftUI
import Combine
import AppUpdater
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    private var statusItem: NSStatusItem!
    private let auth = CookieAuthService.shared
    private lazy var usageStore = UsageStore(auth: auth)
    private var floatingWindow: FloatingWidgetWindow?
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let appUpdater = AppUpdater(owner: "castdrian", repo: "claudemon")
    private var appActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "claudemon")

        buildMenu()

        usageStore.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.buildMenu() }
            .store(in: &cancellables)

        auth.$authState
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

        SettingsStore.shared.$showWidgetOnlyWhenClaudeFocused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFloatingWidgetVisibility() }
            .store(in: &cancellables)

        if auth.authState == .signedOut {
            auth.beginSignIn()
        }

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

        if let snapshot = usageStore.snapshot {
            menu.addItem(withTitle: "Session: \(Int((snapshot.session?.utilization ?? 0).rounded()))%", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Weekly: \(Int((snapshot.weekly?.utilization ?? 0).rounded()))%", action: nil, keyEquivalent: "")
            if let percent = snapshot.credit?.percentUsed {
                menu.addItem(withTitle: "Credits: \(Int(percent.rounded()))%", action: nil, keyEquivalent: "")
            }
            menu.addItem(.separator())
        } else if let error = usageStore.lastError {
            menu.addItem(withTitle: error, action: nil, keyEquivalent: "")
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

        switch auth.authState {
        case .signedIn:
            menu.addItem(Self.item("Sign Out", symbol: "person.crop.circle.badge.xmark", action: #selector(signOut)))
        case .expired:
            menu.addItem(Self.item("Sign In Again…", symbol: "person.crop.circle.badge.exclamationmark", action: #selector(signIn)))
        case .signedOut:
            menu.addItem(Self.item("Sign In…", symbol: "person.crop.circle.badge.plus", action: #selector(signIn)))
        }

        menu.addItem(.separator())
        menu.addItem(Self.item("Support claudemon on Ko-fi…", symbol: "cup.and.saucer", action: #selector(openKofi)))
        menu.addItem(.separator())
        menu.addItem(Self.item("Quit claudemon", symbol: "power", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private static func item(_ title: String, symbol: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.image = image
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

    /// The single place that decides whether the panel should be on screen —
    /// driven by the master toggle, and (when enabled) by whether Claude
    /// desktop is the frontmost app. Keeps the same window instance around
    /// rather than recreating it, so a dragged/snapped position survives
    /// being hidden and shown again.
    private func updateFloatingWidgetVisibility() {
        guard SettingsStore.shared.showFloatingWidget else {
            floatingWindow?.orderOut(nil)
            return
        }

        if SettingsStore.shared.showWidgetOnlyWhenClaudeFocused {
            let isClaudeFocused = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.claudeDesktopBundleID
            setWidgetWindowVisible(isClaudeFocused)
        } else {
            setWidgetWindowVisible(true)
        }
    }

    private func setWidgetWindowVisible(_ visible: Bool) {
        guard visible else {
            floatingWindow?.orderOut(nil)
            return
        }
        if floatingWindow == nil {
            floatingWindow = FloatingWidgetWindow(usageStore: usageStore)
        }
        floatingWindow?.orderFrontRegardless()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(usageStore: usageStore, auth: auth)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "claudemon settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func signIn() {
        auth.beginSignIn()
    }

    @objc private func signOut() {
        auth.signOut()
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
        alert.informativeText = "claudemon \(release.tagName) is ready to install."
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            appUpdater.install(bundle)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
