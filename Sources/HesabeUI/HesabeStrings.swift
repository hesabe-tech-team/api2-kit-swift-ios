@_exported import Hesabe
import Foundation

/// The few words the SDK shows itself. English or Arabic by the device language;
/// replace any of them to match your app.
public struct HesabeStrings: Sendable, Hashable {
    public var cancel: String
    public var chooseMethod: String
    public var confirming: String
    public var processing: String
    public var paid: String
    public var notPaid: String
    public var pending: String
    public var unconfirmed: String
    public var tryAgain: String

    public init(
        cancel: String, chooseMethod: String, confirming: String, processing: String,
        paid: String, notPaid: String, pending: String, unconfirmed: String, tryAgain: String
    ) {
        self.cancel = cancel
        self.chooseMethod = chooseMethod
        self.confirming = confirming
        self.processing = processing
        self.paid = paid
        self.notPaid = notPaid
        self.pending = pending
        self.unconfirmed = unconfirmed
        self.tryAgain = tryAgain
    }

    public static let english = HesabeStrings(
        cancel: "Cancel",
        chooseMethod: "Pay with",
        confirming: "Confirming your payment…",
        processing: "Processing",
        paid: "Payment complete",
        notPaid: "Payment not completed",
        pending: "Your payment is being processed",
        unconfirmed: "We couldn't confirm this payment yet",
        tryAgain: "Try again"
    )

    public static let arabic = HesabeStrings(
        cancel: "إلغاء",
        chooseMethod: "ادفع بواسطة",
        confirming: "جارٍ تأكيد الدفع…",
        processing: "جارٍ المعالجة",
        paid: "تم الدفع",
        notPaid: "لم يكتمل الدفع",
        pending: "عملية الدفع قيد المعالجة",
        unconfirmed: "تعذّر تأكيد الدفع حتى الآن",
        tryAgain: "أعد المحاولة"
    )

    /// Arabic when the device's first language is Arabic, English otherwise.
    public static var automatic: HesabeStrings {
        Locale.preferredLanguages.first?.hasPrefix("ar") == true ? .arabic : .english
    }

    /// The line shown for a settled payment, and whether it reads as a success.
    func summary(of result: PaymentResult) -> (succeeded: Bool, message: String)? {
        switch result {
        case .paid: return (true, paid)
        case .failed: return (false, notPaid)
        case .pending: return (false, pending)
        case .unconfirmed: return (false, unconfirmed)
        case .canceled, .notStarted: return nil
        }
    }
}
