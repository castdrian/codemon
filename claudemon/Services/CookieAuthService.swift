import Foundation
import WebKit
import Combine

extension Notification.Name {
    static let claudemonDidSignIn = Notification.Name("claudemonDidSignIn")
    static let claudemonDidSignOut = Notification.Name("claudemonDidSignOut")
}

@MainActor
final class CookieAuthService: ObservableObject {
    static let shared = CookieAuthService()

    @Published private(set) var authState: AuthState
    @Published private(set) var cookieHeader: String?

    let websiteDataStore = WKWebsiteDataStore.default()
    private var loginWindowController: LoginWindowController?

    private init() {
        let stored = KeychainStore.load(account: "cookie")
        cookieHeader = stored
        authState = stored == nil ? .signedOut : .signedIn
    }

    func beginSignIn() {
        if loginWindowController == nil {
            loginWindowController = LoginWindowController(dataStore: websiteDataStore) { [weak self] header in
                self?.handleCaptured(cookieHeader: header)
            }
        }
        loginWindowController?.showWindow()
    }

    func signOut() {
        KeychainStore.delete(account: "cookie")
        KeychainStore.delete(account: "orgId")
        cookieHeader = nil
        authState = .signedOut

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        websiteDataStore.fetchDataRecords(ofTypes: types) { [websiteDataStore] records in
            let claudeRecords = records.filter { $0.displayName.contains("claude.ai") }
            websiteDataStore.removeData(ofTypes: types, for: claudeRecords) {}
        }

        NotificationCenter.default.post(name: .claudemonDidSignOut, object: nil)
    }

    func markExpired() {
        guard authState == .signedIn else { return }
        authState = .expired
    }

    private func handleCaptured(cookieHeader header: String) {
        KeychainStore.save(header, account: "cookie")
        KeychainStore.delete(account: "orgId")
        cookieHeader = header
        authState = .signedIn
        loginWindowController?.close()
        loginWindowController = nil
        NotificationCenter.default.post(name: .claudemonDidSignIn, object: nil)
    }
}
