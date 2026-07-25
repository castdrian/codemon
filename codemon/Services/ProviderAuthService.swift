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
                try? LocalCredentialsStore.load(for: provider)
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
}
