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
    private var orgId: String?
    private var cancellables = Set<AnyCancellable>()

    init(provider: UsageProvider, refreshInterval: TimeInterval) {
        self.provider = provider
        self.auth = ProviderAuthService(provider: provider)
        self.refreshInterval = refreshInterval
        self.orgId = KeychainStore.load(account: "\(provider.rawValue).orgId")
        self.accountInfo = Self.loadCachedAccountInfo(for: provider)

        auth.$authState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .signedOut {
                    self.reset()
                } else if state == .signedIn {
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)

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
        guard let cookieHeader = auth.cookieHeader else {
            lastError = "Not signed in"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            switch provider {
            case .claude:
                if orgId == nil || accountInfo == nil {
                    let bootstrap = try await claudeClient.fetchBootstrap(cookieHeader: cookieHeader)
                    orgId = bootstrap.orgId
                    KeychainStore.save(bootstrap.orgId, account: "\(provider.rawValue).orgId")
                    accountInfo = bootstrap.account
                    Self.cacheAccountInfo(bootstrap.account, for: provider)
                }
                guard let orgId else { return }
                snapshot = try await claudeClient.fetchUsage(cookieHeader: cookieHeader, orgId: orgId)
            case .codex:
                let result = try await codexClient.fetchUsage(cookieHeader: cookieHeader)
                snapshot = result.snapshot
                accountInfo = result.account
                Self.cacheAccountInfo(result.account, for: provider)
            }
            lastError = nil
        } catch UsageAPIError.unauthorized {
            auth.markExpired()
            lastError = "Session expired — please sign in again"
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
        orgId = nil
        lastError = nil
        KeychainStore.delete(account: "\(provider.rawValue).orgId")
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
