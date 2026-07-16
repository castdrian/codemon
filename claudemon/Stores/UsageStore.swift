import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var accountInfo: AccountInfo?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let apiClient = UsageAPIClient()
    private let auth: CookieAuthService
    private var timer: Timer?
    private var refreshInterval: TimeInterval
    private var signInObserver: NSObjectProtocol?
    private var signOutObserver: NSObjectProtocol?
    private var orgId: String?

    init(auth: CookieAuthService, refreshInterval: TimeInterval = 120) {
        self.auth = auth
        self.refreshInterval = refreshInterval
        self.orgId = KeychainStore.load(account: "orgId")
        self.accountInfo = Self.loadCachedAccountInfo()

        signInObserver = NotificationCenter.default.addObserver(
            forName: .claudemonDidSignIn, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }

        signOutObserver = NotificationCenter.default.addObserver(
            forName: .claudemonDidSignOut, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSignOut()
            }
        }

        startTimer()
        Task { await refresh() }
    }

    deinit {
        timer?.invalidate()
        if let signInObserver {
            NotificationCenter.default.removeObserver(signInObserver)
        }
        if let signOutObserver {
            NotificationCenter.default.removeObserver(signOutObserver)
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard let cookie = auth.cookieHeader else {
            lastError = "Not signed in"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if orgId == nil || accountInfo == nil {
                let bootstrap = try await apiClient.fetchBootstrap(cookieHeader: cookie)
                orgId = bootstrap.orgId
                accountInfo = bootstrap.account
                Self.cacheAccountInfo(bootstrap.account)
            }

            guard let orgId else { return }
            let result = try await apiClient.fetchUsage(cookieHeader: cookie, orgId: orgId)
            snapshot = result
            lastError = nil
        } catch UsageAPIError.unauthorized {
            auth.markExpired()
            lastError = "Session expired — please sign in again"
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleSignOut() {
        snapshot = nil
        accountInfo = nil
        orgId = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.accountInfoDefaultsKey)
    }

    private static let accountInfoDefaultsKey = "cachedAccountInfo"

    private static func loadCachedAccountInfo() -> AccountInfo? {
        guard let data = UserDefaults.standard.data(forKey: accountInfoDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(AccountInfo.self, from: data)
    }

    private static func cacheAccountInfo(_ info: AccountInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: accountInfoDefaultsKey)
    }
}
