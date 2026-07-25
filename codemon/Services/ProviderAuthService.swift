import Foundation
import WebKit
import Combine

@MainActor
final class ProviderAuthService: ObservableObject {
    @Published private(set) var authState: AuthState
    @Published private(set) var cookieHeader: String?

    let provider: UsageProvider
    let websiteDataStore = WKWebsiteDataStore.default()
    private var loginWindowController: LoginWindowController?

    init(provider: UsageProvider) {
        self.provider = provider
        let stored = KeychainStore.load(account: "\(provider.rawValue).cookie")
        cookieHeader = stored
        authState = stored == nil ? .signedOut : .signedIn
    }

    func beginSignIn() {
        if loginWindowController == nil {
            loginWindowController = LoginWindowController(provider: provider, dataStore: websiteDataStore) { [weak self] header in
                self?.handleCaptured(cookieHeader: header)
            }
        }
        clearProviderWebsiteData { [weak self] in
            self?.loginWindowController?.showWindow()
        }
    }

    func signOut() {
        KeychainStore.delete(account: "\(provider.rawValue).cookie")
        cookieHeader = nil
        authState = .signedOut
        clearProviderWebsiteData {}
    }

    private func clearProviderWebsiteData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        websiteDataStore.fetchDataRecords(ofTypes: types) { [websiteDataStore, provider] records in
            let matchingRecords = records.filter { record in
                provider.cookieDomains.contains { record.displayName.contains($0) }
            }
            websiteDataStore.removeData(ofTypes: types, for: matchingRecords) {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    func markExpired() {
        guard authState == .signedIn else { return }
        authState = .expired
    }

    private func handleCaptured(cookieHeader header: String) {
        KeychainStore.save(header, account: "\(provider.rawValue).cookie")
        cookieHeader = header
        authState = .signedIn
        loginWindowController?.close()
        loginWindowController = nil
    }
}
