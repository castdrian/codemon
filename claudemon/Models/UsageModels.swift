import Foundation

struct UsageWindow: Equatable {
    var utilization: Double
    var resetsAt: Date?
}

struct CreditUsage: Equatable {
    var remaining: Double?
    var limit: Double?
    var used: Double?
    var percentUsed: Double?
    var currency: String?
    var decimalPlaces: Int
}

struct UsageSnapshot: Equatable {
    var session: UsageWindow?
    var weekly: UsageWindow?
    var credit: CreditUsage?
    var fetchedAt: Date
}

struct AccountInfo: Equatable, Codable {
    var displayName: String
    var planLabel: String
}

enum AuthState: Equatable {
    case signedOut
    case signedIn
    case expired
}
