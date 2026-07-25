import Foundation

enum CreditBaselineStore {
    private static func key(for provider: UsageProvider) -> String {
        "creditBaseline.\(provider.rawValue)"
    }

    static func baseline(for provider: UsageProvider) -> Double? {
        let stored = UserDefaults.standard.double(forKey: key(for: provider))
        return stored > 0 ? stored : nil
    }

    static func reconcile(balance: Double, for provider: UsageProvider) -> Double? {
        guard balance > 0 else {
            UserDefaults.standard.removeObject(forKey: key(for: provider))
            return nil
        }

        guard let stored = baseline(for: provider), stored >= balance else {
            UserDefaults.standard.set(balance, forKey: key(for: provider))
            return balance
        }
        return stored
    }
}
