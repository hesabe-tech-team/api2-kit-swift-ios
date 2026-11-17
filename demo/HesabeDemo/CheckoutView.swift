import HesabeUI
import SwiftUI

/// One product, a quantity, and every way of paying for it the SDK offers.
@MainActor
struct CheckoutView: View {
    private let backend = Backend(baseURL: Config.backend)

    @State private var quantity = 1
    /// Asks the server for a session whose card form offers to save the card.
    @State private var offersCardSaving = false
    /// The session the checkout sheet is paying. Non-nil presents the sheet.
    @State private var sheetSession: HesabeSession?
    @State private var sheetMethods: [PaymentMethod] = []
    /// The session behind the Apple Pay button. A session is single use, so the button
    /// gets a new one whenever the quantity changes or a payment ends.
    @State private var applePaySession: HesabeSession?
    @State private var applePayRound = 0
    /// The customer's saved cards, as the server lists them.
    @State private var cards: [HesabeSavedCard] = []
    /// The saved card the customer is being asked to confirm a charge on.
    @State private var cardToCharge: HesabeSavedCard?
    @State private var isBusy = false
    @State private var outcome: Outcome?

    private var total: Decimal { Config.unitPrice * Decimal(quantity) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your order") {
                    Stepper("Sticker pack × \(quantity)", value: $quantity, in: 1...20)
                    LabeledContent("Total", value: "KWD \(hesabeAmount(total))")
                }

                Section {
                    if Config.applePayPage != nil {
                        applePayButton
                    }
                    Button("Choose a method") { pay(with: [.knet, .card, .amex]) }
                    Button("KNET") { pay(with: [.knet]) }
                    Button("Card") { pay(with: [.card]) }
                    Button("Hesabe's page, every method") { pay(with: []) }
                    Toggle("Offer to save the card", isOn: $offersCardSaving)
                } header: {
                    Text("Pay")
                } footer: {
                    Text("A card is entered in Hesabe's card form, inside the app.")
                }
                .disabled(isBusy)

                Section {
                    ForEach(cards) { card in
                        Button { cardToCharge = card } label: { SavedCardRow(card: card) }
                            .swipeActions {
                                Button("Remove", role: .destructive) { remove(card) }
                            }
                    }
                    Button("Add a card") { addCard() }
                } header: {
                    Text("Saved cards")
                } footer: {
                    Text("Tap a card to pay with it. The server charges it: no page, no 3-D Secure.")
                }
                .disabled(isBusy)

                if let outcome {
                    Section("Result") {
                        Label(outcome.title, systemImage: outcome.symbol)
                            .foregroundStyle(outcome.succeeded ? Color.green : Color.primary)
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
        .confirmationDialog(
            "Pay KWD \(hesabeAmount(total))?", isPresented: isConfirmingCharge,
            titleVisibility: .visible, presenting: cardToCharge
        ) { card in
            Button("Pay with \(card.displayName)") { charge(card) }
        }
        .task { await loadCards() }
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
            let session = try await backend.createSession(quantity: quantity)
            if !Task.isCancelled { applePaySession = session }
        } catch {
            if !Task.isCancelled { outcome = Outcome(error) }
        }
    }

    // MARK: - Checkout sheet

    private func pay(with methods: [PaymentMethod]) {
        present(methods: methods) {
            try await backend.createSession(quantity: quantity, saveCard: offersCardSaving)
        }
    }

    /// A session with amount 0.000: the sheet shows the card form and saves the card.
    private func addCard() {
        present(methods: []) { try await backend.createCardSession() }
    }

    private func present(
        methods: [PaymentMethod], session create: @escaping @MainActor () async throws -> HesabeSession
    ) {
        isBusy = true
        outcome = nil
        Task {
            defer { isBusy = false }
            do {
                let session = try await create()
                sheetMethods = methods
                sheetSession = session
            } catch {
                outcome = Outcome(error)
            }
        }
    }

    // MARK: - Saved cards

    private var isConfirmingCharge: Binding<Bool> {
        Binding(get: { cardToCharge != nil }, set: { if !$0 { cardToCharge = nil } })
    }

    private func loadCards() async {
        // A list that cannot be read leaves the last one on screen: paying still works.
        if let list = try? await backend.savedCards() { cards = list }
    }

    private func charge(_ card: HesabeSavedCard) {
        isBusy = true
        outcome = nil
        Task {
            defer { isBusy = false }
            do {
                outcome = Outcome(try await backend.charge(card, quantity: quantity), card: card)
            } catch {
                // The request may have reached Hesabe before the answer was lost.
                outcome = Outcome(
                    title: "Could not confirm",
                    detail: error.localizedDescription
                        + "\nThe card may have been charged. Check before paying again.")
            }
        }
    }

    private func remove(_ card: HesabeSavedCard) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await backend.remove(card)
            } catch {
                outcome = Outcome(error)
            }
            await loadCards()
        }
    }

    // MARK: - Result

    /// Shows what the SDK learned from Hesabe, then what the server learned by asking
    /// Hesabe itself. Only the second one may release an order.
    private func show(_ result: PaymentResult) async {
        var shown = Outcome(result)
        outcome = shown
        switch result {
        case .paid(let transaction):
            // The card form may have saved the card along with the payment.
            await loadCards()
            guard let token = transaction.token else { return }
            do {
                let confirmation = try await backend.confirm(token: token)
                shown.detail += confirmation.paid
                    ? "\nYour server asked Hesabe too: \(confirmation.status). The order can be released."
                    : "\nYour server asked Hesabe and got \(confirmation.status). Do not release the order."
            } catch {
                shown.detail += "\nYour server could not confirm it: \(error.localizedDescription)"
            }
            outcome = shown
        case .cardSaved:
            await loadCards()
        case .failed, .pending, .canceled, .unconfirmed, .notStarted:
            break
        }
    }
}

/// One saved card in the list.
private struct SavedCardRow: View {
    let card: HesabeSavedCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard")
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .foregroundStyle(Color.primary)
                Text("Expires \(card.expiry)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

/// A payment result as the demo shows it.
struct Outcome {
    var title: String
    var detail: String
    var succeeded = false

    var symbol: String { succeeded ? "checkmark.circle.fill" : "info.circle" }

    init(title: String, detail: String, succeeded: Bool = false) {
        self.title = title
        self.detail = detail
        self.succeeded = succeeded
    }

    init(_ result: PaymentResult) {
        switch result {
        case .paid(let transaction):
            self.init(title: "Paid", detail: Self.describe(transaction), succeeded: true)
        case .cardSaved(let transaction):
            self.init(
                title: "Card saved",
                detail: Self.describe(transaction) + "\nNothing was charged. The card is in your saved cards.",
                succeeded: true)
        case .failed(let transaction):
            self.init(title: "Not paid", detail: Self.describe(transaction) + "\nNothing was charged.")
        case .pending(let transaction):
            self.init(
                title: "Processing",
                detail: Self.describe(transaction) + "\nHesabe is still settling it. Don't pay again yet.")
        case .canceled:
            self.init(title: "Cancelled", detail: "Nothing was charged.")
        case .unconfirmed(let error):
            self.init(
                title: "Could not confirm",
                detail: error.localizedDescription
                    + "\nThe payment may have gone through. Check before paying again.")
        case .notStarted(let error):
            self.init(title: "Could not start", detail: "\(error.localizedDescription)\nNothing was charged.")
        }
    }

    /// The server's answer to charging a saved card. It is Hesabe's own answer to the
    /// server, so there is nothing further to confirm.
    init(_ charge: Backend.Charge, card: HesabeSavedCard) {
        let facts = [card.displayName, charge.amount.map { "KWD \($0)" }, charge.reference, charge.status]
            .compactMap { $0 }
            .joined(separator: " · ")
        if charge.paid {
            self.init(
                title: "Paid", detail: facts + "\nYour server charged the card. The order can be released.",
                succeeded: true)
        } else {
            self.init(
                title: "Not paid",
                detail: [facts, charge.message ?? "Hesabe did not take the payment.", "Nothing was charged."]
                    .joined(separator: "\n"))
        }
    }

    init(_ error: Error) {
        self.init(title: "Could not start", detail: error.localizedDescription)
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
