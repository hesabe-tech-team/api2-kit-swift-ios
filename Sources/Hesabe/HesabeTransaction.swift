import Foundation

/// A payment as Hesabe recorded it. Read from `api/transaction/enquire/<token>`.
public struct HesabeTransaction: Sendable, Hashable, Decodable {
    /// Hesabe's status word. `SUCCESSFUL` and `FAILED` are the two observed so far.
    public let status: String
    public let token: String?
    /// The amount charged, with three decimals, as Hesabe writes it.
    public let amount: String?
    /// The order reference your server sent as `orderReferenceNumber`.
    public let orderReference: String?
    public let paymentID: String?
    public let transactionID: String?
    /// Hesabe's name for the method used, for example `KNET`.
    public let paymentType: String?
    /// Kuwait time (UTC+3) with no zone, as Hesabe writes it.
    public let datetime: String?

    /// True only when Hesabe says the money moved.
    public var isPaid: Bool { status.uppercased() == "SUCCESSFUL" }

    /// True when Hesabe recorded the attempt as over without a payment.
    public var isFailed: Bool {
        ["FAILED", "CANCELLED", "CANCELED", "DECLINED"].contains(status.uppercased())
    }

    private enum CodingKeys: String, CodingKey {
        case status, token, amount, datetime
        case orderReference = "reference_number"
        case paymentID = "PaymentID"
        case transactionID = "TransactionID"
        case paymentType = "payment_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        token = Self.text(container, .token)
        amount = Self.text(container, .amount)
        orderReference = Self.text(container, .orderReference)
        paymentID = Self.text(container, .paymentID)
        transactionID = Self.text(container, .transactionID)
        paymentType = Self.text(container, .paymentType)
        datetime = Self.text(container, .datetime)
    }

    /// Hesabe sends ids as strings in some answers and as numbers in others.
    private static func text(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        return nil
    }
}

/// How a payment ended. Every case comes from asking Hesabe, never from the redirect
/// and never from a wallet sheet saying "Done".
///
/// Show it to the customer. Release the order from your server, which asks Hesabe
/// itself: a result that travelled through the device is not proof for fulfilment.
public enum PaymentResult: Sendable, Hashable {
    /// Hesabe confirms the payment.
    case paid(HesabeTransaction)
    /// Hesabe recorded the attempt and it did not go through. Nothing was charged.
    case failed(HesabeTransaction)
    /// Hesabe has the payment and has not settled it. Do not charge again.
    case pending(HesabeTransaction)
    /// The customer closed the payment and Hesabe has no transaction for the session.
    case canceled
    /// The flow ended and the SDK could not find out how. The customer may have been
    /// charged. Ask again with `HesabeClient.settle` or from your server.
    case unconfirmed(HesabeError)
    /// The payment never started. Nothing was charged.
    case notStarted(HesabeError)
}
