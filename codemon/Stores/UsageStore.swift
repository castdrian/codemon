import Foundation
import Combine

@MainActor
final class ProviderUsageStore: ObservableObject, Identifiable {
    let provider: UsageProvider
    let auth: ProviderAuthService

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var accountInfo: AccountInfo?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    var id: UsageProvider { provider }

    private let claudeClient = ClaudeUsageAPIClient()
    private let codexClient = CodexUsageAPIClient()
    private var timer: Timer?
    private var refreshInterval: TimeInterval
    private var cancellables = Set<AnyCancellable>()

    init(provider: UsageProvider, refreshInterval: TimeInterval) {
        self.provider = provider
        self.auth = ProviderAuthService(provider: provider)
        self.refreshInterval = refreshInterval
        self.accountInfo = Self.loadCachedAccountInfo(for: provider)

        startTimer()
        Task { await refresh() }
    }

    deinit {
        timer?.invalidate()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        startTimer()
    }

    func refresh() async {
        guard let credentials = await auth.reload() else {
            reset()
            lastError = provider.credentialsHint
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            switch provider {
            case .claude:
                if accountInfo == nil {
                    let account = try await claudeClient.fetchAccount(
                        accessToken: credentials.accessToken,
                        planHint: credentials.planHint
                    )
                    accountInfo = account
                    Self.cacheAccountInfo(account, for: provider)
                }
                snapshot = try await claudeClient.fetchUsage(accessToken: credentials.accessToken)
            case .codex:
                let result = try await codexClient.fetchUsage(
                    accessToken: credentials.accessToken,
                    accountId: credentials.accountId,
                    accountName: credentials.accountName
                )
                snapshot = result.snapshot
                accountInfo = result.account
                Self.cacheAccountInfo(result.account, for: provider)
            }
            lastError = nil
        } catch UsageAPIError.unauthorized {
            auth.markExpired()
            lastError = provider.expiredHint
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    private func reset() {
        snapshot = nil
        accountInfo = nil
        UserDefaults.standard.removeObject(forKey: Self.accountInfoDefaultsKey(for: provider))
    }

    private static func accountInfoDefaultsKey(for provider: UsageProvider) -> String {
        "cachedAccountInfo.\(provider.rawValue)"
    }

    private static func loadCachedAccountInfo(for provider: UsageProvider) -> AccountInfo? {
        guard let data = UserDefaults.standard.data(forKey: accountInfoDefaultsKey(for: provider)) else { return nil }
        return try? JSONDecoder().decode(AccountInfo.self, from: data)
    }

    private static func cacheAccountInfo(_ info: AccountInfo, for provider: UsageProvider) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: accountInfoDefaultsKey(for: provider))
    }
}

@MainActor
final class UsageStore: ObservableObject {
    let providerStores: [ProviderUsageStore]
    private var cancellables = Set<AnyCancellable>()

    init(refreshInterval: TimeInterval = 120) {
        providerStores = UsageProvider.allCases.map { ProviderUsageStore(provider: $0, refreshInterval: refreshInterval) }
        providerStores.forEach { providerStore in
            providerStore.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        providerStores.forEach { $0.setRefreshInterval(interval) }
    }

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for providerStore in providerStores {
                group.addTask { await providerStore.refresh() }
            }
        }
    }
}
