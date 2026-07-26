import Foundation
import Combine

@MainActor
final class ProviderAuthService: ObservableObject {
    @Published private(set) var authState: AuthState = .signedOut
    @Published private(set) var credentials: ProviderCredentials?

    let provider: UsageProvider
    private var loadTask: Task<ProviderCredentials?, Never>?

    init(provider: UsageProvider) {
        self.provider = provider
    }

    @discardableResult
    func reload() async -> ProviderCredentials? {
        let task = loadTask ?? {
            let provider = self.provider
            let task = Task.detached(priority: .utility) {
                await Self.loadRefreshingIfNeeded(for: provider)
            }
            loadTask = task
            return task
        }()

        let loaded = await task.value
        loadTask = nil

        guard let loaded else {
            credentials = nil
            authState = .signedOut
            return nil
        }
        credentials = loaded
        authState = loaded.isExpired ? .expired : .signedIn
        return loaded
    }

    func markExpired() {
        guard authState == .signedIn else { return }
        authState = .expired
    }

    private static let refreshLeeway: TimeInterval = 300

    private static func loadRefreshingIfNeeded(for provider: UsageProvider) async -> ProviderCredentials? {
        guard let credentials = try? LocalCredentialsStore.load(for: provider) else { return nil }
        guard provider == .claude, credentials.expires(within: refreshLeeway) else { return credentials }
        guard let refreshToken = credentials.refreshToken else { return credentials }

        do {
            return try await LocalCredentialsStore.refreshClaude(using: refreshToken)
        } catch {
            return (try? LocalCredentialsStore.load(for: provider)) ?? credentials
        }
    }
}
