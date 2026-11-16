import Foundation

/// Everything the SDK can report going wrong. It never carries a key or a card number.
public enum HesabeError: Error, Sendable, Hashable {
    /// The app set something up wrongly. Raised before any payment page opens.
    case configuration(String)
    /// Hesabe could not be reached, or the connection dropped.
    case connection(String)
    /// Hesabe refused the session: it is malformed, already used, or from the other
    /// environment. Create a new one on your server.
    case rejected(String)
    /// The payment flow ended and Hesabe has no transaction for the session yet.
    case noTransaction
}

extension HesabeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configuration(let message): "Hesabe is not set up correctly: \(message)"
        case .connection(let message): "Could not reach Hesabe: \(message)"
        case .rejected(let message): "Hesabe did not accept the payment session: \(message)"
        case .noTransaction: "Hesabe has no record of this payment yet."
        }
    }
}
