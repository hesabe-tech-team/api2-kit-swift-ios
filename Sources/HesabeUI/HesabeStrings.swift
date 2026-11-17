@_exported import Hesabe
import Foundation

/// The few words the SDK shows itself. English or Arabic by the device language;
/// replace any of them to match your app.
public struct HesabeStrings: Sendable, Hashable {
    /// The language Hesabe's card form is asked for: `en` or `ar`.
    public var languageCode: String
    public var cancel: String
    public var chooseMethod: String
    /// The title above the card form when the session saves a card and charges nothing.
    public var addCard: String
    public var confirming: String
    public var processing: String
    public var paid: String
    public var cardSaved: String
    public var notPaid: String
    public var pending: String
    public var unconfirmed: String
    public var tryAgain: String

    public init(
        languageCode: String, cancel: String, chooseMethod: String, addCard: String,
        confirming: String, processing: String, paid: String, cardSaved: String,
        notPaid: String, pending: String, unconfirmed: String, tryAgain: String
    ) {
        self.languageCode = languageCode
        self.cancel = cancel
        self.chooseMethod = chooseMethod
        self.addCard = addCard
        self.confirming = confirming
        self.processing = processing
        self.paid = paid
        self.cardSaved = cardSaved
        self.notPaid = notPaid
        self.pending = pending
        self.unconfirmed = unconfirmed
        self.tryAgain = tryAgain
    }

    public static let english = HesabeStrings(
        languageCode: "en",
        cancel: "Cancel",
        chooseMethod: "Pay with",
        addCard: "Add a card",
        confirming: "Confirming your payment…",
        processing: "Processing",
        paid: "Payment complete",
        cardSaved: "Card saved",
        notPaid: "Payment not completed",
        pending: "Your payment is being processed",
        unconfirmed: "We couldn't confirm this payment yet",
        tryAgain: "Try again"
    )

    public static let arabic = HesabeStrings(
        languageCode: "ar",
        cancel: "إلغاء",
        chooseMethod: "ادفع بواسطة",
        addCard: "إضافة بطاقة",
        confirming: "جارٍ تأكيد الدفع…",
        processing: "جارٍ المعالجة",
        paid: "تم الدفع",
        cardSaved: "تم حفظ البطاقة",
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
        case .cardSaved: return (true, cardSaved)
        case .failed: return (false, notPaid)
        case .pending: return (false, pending)
        case .unconfirmed: return (false, unconfirmed)
        case .canceled, .notStarted: return nil
        }
    }
}
