import Foundation

/// What Hesabe says about a session before anything is paid: the amount and the
/// payment methods enabled for it. Read from `api/checkout-details`, which takes the
/// session's `data` and no merchant key.
public struct CheckoutDetails: Sendable, Hashable, Decodable {
    /// Hesabe's token for the session. The outcome is looked up by it.
    public let token: String
    public let amount: Decimal
    public let currency: String
    /// The payment type the server asked for. `0` leaves the choice to the customer.
    public let requestedMethod: PaymentMethod
    /// Every payment type enabled for this session.
    public let paymentMethods: [PaymentMethod]
    /// The Apple Pay types among them, as Hesabe lists them for its Apple Pay script.
    public let applePayMethods: [PaymentMethod]
    /// The card payment types Hesabe's embedded card form takes for this session:
    /// `[2]` on the sandbox (November 2026). The SDK shows the form for these and
    /// Hesabe's payment page for every other method.
    public let embeddedCardMethods: [PaymentMethod]
    /// True when your server put a Hesabe customer on the session (`customer_id`).
    public let hasCustomer: Bool
    /// True when the card form offers to save the card: `saveCard` with a customer.
    public let offersCardSaving: Bool

    /// True for a session that saves a card and charges nothing: amount `0.000` with a
    /// customer. The card form then reads "Save Card" in place of "Pay".
    public var isCardVerification: Bool { amount == 0 && hasCustomer }

    /// The amount as Hesabe writes it: the currency and three decimals, `KWD 1.000`.
    public var formattedAmount: String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 3, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        let digits = formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
        return "\(currency) \(digits)"
    }

    private enum CodingKeys: String, CodingKey {
        case token, amount, currency, paymentTypeId, paymentMethods, applePay
        case hasCustomer, merchantSaveCard, activeDirectGatewayIds
    }

    private struct ApplePayEntry: Decodable {
        let id: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "KWD"

        // Hesabe sends the amount as a number here and as a string elsewhere, and the
        // payment type as "0" (sandbox, November 2026). Both spellings are read.
        if let text = try? container.decode(String.self, forKey: .amount) {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: container, debugDescription: "amount is not a number")
            }
            amount = value
        } else {
            amount = try container.decode(Decimal.self, forKey: .amount)
        }

        if let text = try? container.decode(String.self, forKey: .paymentTypeId) {
            requestedMethod = PaymentMethod(rawValue: Int(text) ?? 0)
        } else {
            requestedMethod = PaymentMethod(
                rawValue: try container.decodeIfPresent(Int.self, forKey: .paymentTypeId) ?? 0)
        }

        paymentMethods = try container.decodeIfPresent([Int].self, forKey: .paymentMethods)?
            .map(PaymentMethod.init(rawValue:)) ?? []
        applePayMethods = try container.decodeIfPresent([ApplePayEntry].self, forKey: .applePay)?
            .map { PaymentMethod(rawValue: $0.id) } ?? []
        embeddedCardMethods = try container.decodeIfPresent([Int].self, forKey: .activeDirectGatewayIds)?
            .map(PaymentMethod.init(rawValue:)) ?? []
        hasCustomer = try container.decodeIfPresent(Bool.self, forKey: .hasCustomer) ?? false
        offersCardSaving = try container.decodeIfPresent(Bool.self, forKey: .merchantSaveCard) ?? false
    }
}
