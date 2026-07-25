import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject private var prefs = SettingsStore.shared

    var body: some View {
        Form {
            Section("Accounts") {
                ForEach(usageStore.providerStores) { providerStore in
                    ProviderAccountRow(providerStore: providerStore)
                }
            }

            Section("Widget") {
                Toggle("Show floating widget", isOn: $prefs.showFloatingWidget)
                Toggle("Only when Claude or Codex is focused", isOn: $prefs.showWidgetOnlyWhenProviderFocused)
                    .disabled(!prefs.showFloatingWidget)
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

            ForEach(usageStore.providerStores.filter { $0.lastError != nil }) { providerStore in
                if let error = providerStore.lastError {
                    Section(providerStore.provider.displayName) {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct ProviderAccountRow: View {
    @ObservedObject var providerStore: ProviderUsageStore

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(providerStore.provider.displayName)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusLabel)
                    .foregroundStyle(statusColor)
                if providerStore.auth.authState != .signedIn {
                    Text("run `\(providerStore.provider.cliName)` in a terminal to log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusLabel: String {
        switch providerStore.auth.authState {
        case .signedIn: return providerStore.accountInfo?.displayName ?? "Signed in"
        case .expired: return "Credentials expired"
        case .signedOut: return "Not signed in"
        }
    }

    private var statusColor: Color {
        switch providerStore.auth.authState {
        case .signedIn: return .green
        case .expired: return .orange
        case .signedOut: return .secondary
        }
    }
}
