import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var auth: CookieAuthService
    @ObservedObject private var prefs = SettingsStore.shared

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text(statusLabel)
                        .foregroundStyle(statusColor)
                    Spacer()
                    Button(auth.authState == .signedIn ? "Sign Out" : "Sign In…") {
                        if auth.authState == .signedIn {
                            auth.signOut()
                        } else {
                            auth.beginSignIn()
                        }
                    }
                }
            }

            Section("Widget") {
                Toggle("Show floating widget", isOn: $prefs.showFloatingWidget)
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                KeyboardShortcuts.Recorder("Toggle widget:", name: .toggleWidget)
            }

            Section("Refresh") {
                Picker("Refresh every", selection: $prefs.refreshIntervalMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("2 minutes").tag(2.0)
                    Text("5 minutes").tag(5.0)
                    Text("10 minutes").tag(10.0)
                }
                .onChange(of: prefs.refreshIntervalMinutes) { newValue in
                    usageStore.setRefreshInterval(newValue * 60)
                }

                Button("Refresh Now") {
                    Task { await usageStore.refresh() }
                }
            }

            if let error = usageStore.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var statusLabel: String {
        switch auth.authState {
        case .signedIn: return "Signed in"
        case .expired: return "Session expired"
        case .signedOut: return "Not signed in"
        }
    }

    private var statusColor: Color {
        switch auth.authState {
        case .signedIn: return .green
        case .expired: return .orange
        case .signedOut: return .secondary
        }
    }
}
