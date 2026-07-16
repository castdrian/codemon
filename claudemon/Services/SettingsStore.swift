import Foundation
import ServiceManagement

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var showFloatingWidget: Bool {
        didSet { defaults.set(showFloatingWidget, forKey: "showFloatingWidget") }
    }
    @Published var refreshIntervalMinutes: Double {
        didSet { defaults.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes") }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private let defaults = UserDefaults.standard

    private init() {
        showFloatingWidget = defaults.object(forKey: "showFloatingWidget") as? Bool ?? true
        refreshIntervalMinutes = defaults.object(forKey: "refreshIntervalMinutes") as? Double ?? 2
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            switch (launchAtLogin, SMAppService.mainApp.status) {
            case (true, .enabled):
                break
            case (true, _):
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("claudemon: launch at login toggle failed: \(error)")
        }
    }
}
