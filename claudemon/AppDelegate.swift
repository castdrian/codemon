import AppKit
import SwiftUI
import Combine
import AppUpdater
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let auth = CookieAuthService.shared
    private lazy var usageStore = UsageStore(auth: auth)
    private var floatingWindow: FloatingWidgetWindow?
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private let appUpdater = AppUpdater(owner: "castdrian", repo: "claudemon")

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

        if SettingsStore.shared.showFloatingWidget {
            showFloatingWidget()
        }

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

        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        menu.addItem(.separator())

        let widgetItem = NSMenuItem(title: "Show Floating Widget", action: #selector(toggleFloatingWidget), keyEquivalent: "")
        widgetItem.state = SettingsStore.shared.showFloatingWidget ? .on : .off
        menu.addItem(widgetItem)

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())

        switch auth.authState {
        case .signedIn:
            menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        case .expired:
            menu.addItem(withTitle: "Sign In Again…", action: #selector(signIn), keyEquivalent: "")
        case .signedOut:
            menu.addItem(withTitle: "Sign In…", action: #selector(signIn), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Support claudemon on Ko-fi…", action: #selector(openKofi), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit claudemon", action: #selector(quit), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func refreshNow() {
        Task { await usageStore.refresh() }
    }

    @objc private func toggleFloatingWidget() {
        SettingsStore.shared.showFloatingWidget.toggle()
        if SettingsStore.shared.showFloatingWidget {
            showFloatingWidget()
        } else {
            floatingWindow?.close()
            floatingWindow = nil
        }
        buildMenu()
    }

    private func showFloatingWidget() {
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
