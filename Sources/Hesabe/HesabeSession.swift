import Foundation

/// One payment, as your server created it with Hesabe's Checkout API.
///
/// It holds the `response.data` string from the Checkout API answer and nothing else.
/// That string opens one payment and cannot create another, so it is safe on the device.
/// The merchant keys that produced it stay on your server.
public struct HesabeSession: Sendable, Hashable {
    /// The hex string Hesabe's payment page and wallet scripts take as `data`.
    public let data: String

    /// - Parameter data: `response.data` from the Checkout API. A session created with
    ///   `embeddedPayment` comes wrapped in base64 JSON; that form is accepted too.
    public init(data: String) throws {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isHex(trimmed) {
            self.data = trimmed
            return
        }
        // An embedded session is base64 JSON {data, token, session_id, ...}. Hesabe's
        // payment page and checkout-details answer 400 for the wrapper and take the
        // inner `data` (sandbox, November 2026).
        guard let decoded = Data(base64Encoded: trimmed),
              let wrapper = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let inner = wrapper["data"] as? String, Self.isHex(inner)
        else {
            throw HesabeError.configuration(
                "the session is not the response.data string from Hesabe's Checkout API")
        }
        self.data = inner
    }

    private static func isHex(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte) || (65...70).contains(byte)
        }
    }
}
