import Foundation
import HesabeUI

/// Everything you change to run the demo against your own account. None of it is
/// secret: the merchant keys live in `demo/server`, never in the app.
enum Config {
    /// The gateway your server creates sessions on.
    static let environment: HesabeEnvironment = .sandbox

    /// Your server. The simulator reaches the Mac on `localhost`; an iPhone needs the
    /// Mac's address on the network, or your deployed server.
    static let backend = URL(string: "http://localhost:4242")!

    /// The `responseUrl` and `failureUrl` your server sends to Hesabe. The same value
    /// as `RETURN_URL` in `demo/server/server.mjs`.
    static let returnURL = URL(string: "https://example.com/hesabe/return")!

    /// The hosted Apple Pay button page, for example
    /// `URL(string: "https://example.com/apple-pay.html")`. `nil` hides the button.
    static let applePayPage: URL? = nil

    /// The Apple Pay payment type on your account: 11 KNET debit, 13 KNET international.
    static let applePayMethod: PaymentMethod = .applePayKNETDebit

    /// The price shown in the app. The server charges its own copy of it.
    static let unitPrice = Decimal(string: "0.250")!

    static var hesabe: HesabeConfiguration {
        HesabeConfiguration(
            environment: environment,
            returnURLs: ReturnURLs(returnURL),
            merchantDisplayName: "Hesabe Demo",
            applePayPageURL: applePayPage)
    }
}

/// The only place a `Decimal` becomes text: three decimals, as Hesabe writes amounts.
func hesabeAmount(_ amount: Decimal) -> String {
    var value = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 3, .plain)
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumIntegerDigits = 1
    formatter.minimumFractionDigits = 3
    formatter.maximumFractionDigits = 3
    return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
}
