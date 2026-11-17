import Foundation

/// A card a customer saved with Hesabe, in the shape of Hesabe's
/// `GET api/direct-payment/cards` answer.
///
/// That call needs the merchant keys, so the app never makes it. Your server does, and
/// can pass each entry of `cards` through unchanged: this type decodes it. The app
/// shows the list, and your server charges the chosen `id` with
/// `POST api/direct-payment/charge-card`.
public struct HesabeSavedCard: Sendable, Hashable, Decodable, Identifiable {
    /// Hesabe's `card_id`. Only your server can charge or remove it.
    public let id: Int
    /// The card number as Hesabe masks it, `****0008`.
    public let maskedNumber: String
    public let expiryMonth: String
    public let expiryYear: String
    /// The scheme as Hesabe writes it, `MASTERCARD` or `VISA`.
    public let brand: String
    public let nameOnCard: String?

    /// The digits Hesabe leaves visible, `0008`.
    public var lastFour: String {
        String(maskedNumber.filter(\.isNumber).suffix(4))
    }

    /// `MM/YY`, as printed on the card.
    public var expiry: String { "\(expiryMonth)/\(expiryYear)" }

    /// A line for a list: `Mastercard •••• 0008`.
    public var displayName: String {
        let names = ["MASTERCARD": "Mastercard", "VISA": "Visa", "AMEX": "American Express"]
        let key = brand.uppercased().replacingOccurrences(of: "_", with: " ")
        return "\(names[key] ?? key.capitalized) •••• \(lastFour)"
    }

    private enum CodingKeys: String, CodingKey {
        case id = "card_id"
        case maskedNumber = "card_number"
        case expiryMonth = "expiry_month"
        case expiryYear = "expiry_year"
        case brand
        case nameOnCard = "name_on_card"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Hesabe sends ids as numbers in some answers and as strings in others.
        if let number = try? container.decode(Int.self, forKey: .id) {
            id = number
        } else if let number = Int(try container.decode(String.self, forKey: .id)) {
            id = number
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "card_id is not a number")
        }
        maskedNumber = try container.decode(String.self, forKey: .maskedNumber)
        expiryMonth = try container.decodeIfPresent(String.self, forKey: .expiryMonth) ?? ""
        expiryYear = try container.decodeIfPresent(String.self, forKey: .expiryYear) ?? ""
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        nameOnCard = try container.decodeIfPresent(String.self, forKey: .nameOnCard)
    }
}
