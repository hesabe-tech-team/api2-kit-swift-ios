import Foundation

/// A payment that was started on this device and whose end the app never saw.
public struct PendingPayment: Sendable, Hashable, Codable {
    public let token: String
    public let environment: HesabeEnvironment
    public let startedAt: Date

    public init(token: String, environment: HesabeEnvironment, startedAt: Date = Date()) {
        self.token = token
        self.environment = environment
        self.startedAt = startedAt
    }
}

/// The session tokens of payments in flight, kept across launches.
///
/// Hesabe has no idempotency keys, and a customer can pay in a banking app and never
/// come back. So a token is written here before the payment page opens and removed
/// only when Hesabe reports the payment paid, failed or never attempted. What is left
/// is settled by `HesabeClient.recoverPayments()` at the next launch.
public enum HesabePendingPayments {
    private static let storageKey = "com.hesabe.sdk.pendingPayments"

    /// Payments still waiting for an outcome, oldest first.
    public static func all(in store: UserDefaults = .standard) -> [PendingPayment] {
        guard let data = store.data(forKey: storageKey),
              let pending = try? JSONDecoder().decode([PendingPayment].self, from: data)
        else { return [] }
        return pending.sorted { $0.startedAt < $1.startedAt }
    }

    /// Forgets a payment whose outcome is known.
    public static func resolve(_ token: String, in store: UserDefaults = .standard) {
        write(all(in: store).filter { $0.token != token }, to: store)
    }

    /// Drops payments older than `age`, a week by default: a session does not stay
    /// payable for ever.
    public static func prune(olderThan age: TimeInterval = 60 * 60 * 24 * 7,
                             in store: UserDefaults = .standard) {
        let cutoff = Date().addingTimeInterval(-age)
        write(all(in: store).filter { $0.startedAt > cutoff }, to: store)
    }

    package static func track(_ payment: PendingPayment, in store: UserDefaults = .standard) {
        var pending = all(in: store)
        guard !pending.contains(where: { $0.token == payment.token }) else { return }
        pending.append(payment)
        write(pending, to: store)
    }

    private static func write(_ pending: [PendingPayment], to store: UserDefaults) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        store.set(data, forKey: storageKey)
    }
}
