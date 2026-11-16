import HesabeUI
import SwiftUI

/// One product, a quantity, and every way of paying for it the SDK offers.
@MainActor
struct CheckoutView: View {
    private let backend = Backend(baseURL: Config.backend)

    @State private var quantity = 1
    /// The session the checkout sheet is paying. Non-nil presents the sheet.
    @State private var sheetSession: HesabeSession?
    @State private var sheetMethods: [PaymentMethod] = []
    /// The session behind the Apple Pay button. A session is single use, so the button
    /// gets a new one whenever the quantity changes or a payment ends.
    @State private var applePaySession: HesabeSession?
    @State private var applePayRound = 0
    @State private var isStarting = false
    @State private var outcome: Outcome?

    private var total: Decimal { Config.unitPrice * Decimal(quantity) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your order") {
                    Stepper("Sticker pack × \(quantity)", value: $quantity, in: 1...20)
                    LabeledContent("Total", value: "KWD \(hesabeAmount(total))")
                }

                Section("Pay") {
                    if Config.applePayPage != nil {
                        applePayButton
                    }
                    Button("Choose a method") { pay(with: [.knet, .card, .amex]) }
                    Button("KNET") { pay(with: [.knet]) }
                    Button("Hesabe's page, every method") { pay(with: []) }
                }
                .disabled(isStarting)

                if let outcome {
                    Section("Result") {
                        Label(outcome.title, systemImage: outcome.symbol)
                            .foregroundStyle(outcome.isPaid ? Color.green : Color.primary)
                        Text(outcome.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Hesabe Demo")
        }
        .hesabeCheckout(session: $sheetSession, configuration: Config.hesabe, methods: sheetMethods) { result in
            Task { await show(result) }
        }
        .task(id: ApplePayKey(quantity: quantity, round: applePayRound)) {
            await prepareApplePay()
        }
    }

    // MARK: - Apple Pay

    @ViewBuilder
    private var applePayButton: some View {
        if let applePaySession {
            HesabeApplePayButton(
                session: applePaySession, configuration: Config.hesabe, method: Config.applePayMethod
            ) { result in
                Task {
                    await show(result)
                    applePayRound += 1
                }
            }
            .id(applePaySession)
            .listRowInsets(EdgeInsets())
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private struct ApplePayKey: Equatable {
        let quantity: Int
        let round: Int
    }

    private func prepareApplePay() async {
        guard Config.applePayPage != nil else { return }
        applePaySession = nil
        do {
            let created = try await backend.createSession(quantity: quantity)
            if !Task.isCancelled { applePaySession = created.session }
        } catch {
            if !Task.isCancelled { outcome = Outcome(error) }
        }
    }

    // MARK: - Checkout sheet

    private func pay(with methods: [PaymentMethod]) {
        isStarting = true
        outcome = nil
        Task {
            defer { isStarting = false }
            do {
                let created = try await backend.createSession(quantity: quantity)
                sheetMethods = methods
                sheetSession = created.session
            } catch {
                outcome = Outcome(error)
            }
        }
    }

    // MARK: - Result

    /// Shows what the SDK learned from Hesabe, then what the server learned by asking
    /// Hesabe itself. Only the second one may release an order.
    private func show(_ result: PaymentResult) async {
        var shown = Outcome(result)
        outcome = shown
        guard case .paid(let transaction) = result, let token = transaction.token else { return }
        do {
            let confirmation = try await backend.confirm(token: token)
            shown.detail += confirmation.paid
                ? "\nYour server asked Hesabe too: \(confirmation.status). The order can be released."
                : "\nYour server asked Hesabe and got \(confirmation.status). Do not release the order."
        } catch {
            shown.detail += "\nYour server could not confirm it: \(error.localizedDescription)"
        }
        outcome = shown
    }
}

/// A payment result as the demo shows it.
struct Outcome {
    var title: String
    var detail: String
    var isPaid = false

    var symbol: String { isPaid ? "checkmark.circle.fill" : "info.circle" }

    init(_ result: PaymentResult) {
        switch result {
        case .paid(let transaction):
            title = "Paid"
            detail = Self.describe(transaction)
            isPaid = true
        case .failed(let transaction):
            title = "Not paid"
            detail = Self.describe(transaction) + "\nNothing was charged."
        case .pending(let transaction):
            title = "Processing"
            detail = Self.describe(transaction) + "\nHesabe is still settling it. Don't pay again yet."
        case .canceled:
            title = "Cancelled"
            detail = "Nothing was charged."
        case .unconfirmed(let error):
            title = "Could not confirm"
            detail = "\(error.localizedDescription)\nThe payment may have gone through. Check before paying again."
        case .notStarted(let error):
            title = "Could not start"
            detail = "\(error.localizedDescription)\nNothing was charged."
        }
    }

    init(_ error: Error) {
        title = "Could not start"
        detail = error.localizedDescription
    }

    private static func describe(_ transaction: HesabeTransaction) -> String {
        [
            transaction.paymentType,
            transaction.amount.map { "KWD \($0)" },
            transaction.orderReference,
            transaction.status,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
