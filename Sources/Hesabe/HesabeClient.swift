import Foundation

/// The calls a device can make to Hesabe with a session and no merchant key: read the
/// session, build the payment page's address, and ask how the payment ended.
///
/// Creating a session, refunds and everything else that needs the access code or the
/// secret key belong on your server.
public struct HesabeClient: Sendable {
    /// Sends one request. Replaced in tests.
    package typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public let environment: HesabeEnvironment
    private let transport: Transport
    private let pause: @Sendable (TimeInterval) async -> Void

    public init(environment: HesabeEnvironment) {
        self.init(environment: environment, transport: Self.urlSession, pause: Self.sleep)
    }

    package init(
        environment: HesabeEnvironment,
        transport: @escaping Transport,
        pause: @escaping @Sendable (TimeInterval) async -> Void
    ) {
        self.environment = environment
        self.transport = transport
        self.pause = pause
    }

    // MARK: - Session

    /// Reads the session's amount and enabled payment methods.
    ///
    /// - Throws: `HesabeError.rejected` when Hesabe does not accept the session, which
    ///   is also its answer for one that was already paid.
    public func details(for session: HesabeSession) async throws -> CheckoutDetails {
        let url = endpoint("api/checkout-details", query: [URLQueryItem(name: "data", value: session.data)])
        let (data, response) = try await send(url)
        guard let envelope = try? JSONDecoder().decode(DetailsEnvelope.self, from: data) else {
            throw HesabeError.rejected("Hesabe answered HTTP \(response.statusCode)")
        }
        guard response.statusCode == 200, envelope.status, let details = envelope.response else {
            throw HesabeError.rejected(envelope.message ?? "Hesabe answered HTTP \(response.statusCode)")
        }
        return details
    }

    /// The address of the payment page for a session.
    ///
    /// - Parameter method: the payment type to open directly. A session created with
    ///   `paymentType` 0 goes straight to that method's page: `paymentType=1` answered
    ///   with a redirect to KNET (sandbox, November 2026). `nil` opens Hesabe's own
    ///   page, which lists every enabled method.
    public func paymentURL(for session: HesabeSession, method: PaymentMethod? = nil) -> URL {
        var query = [URLQueryItem(name: "data", value: session.data)]
        if let method {
            query.append(URLQueryItem(name: "paymentType", value: String(method.rawValue)))
        }
        return endpoint("payment", query: query)
    }

    // MARK: - Outcome

    /// Every attempt Hesabe recorded for a session token. Empty when it has none, which
    /// means no payment reached Hesabe.
    public func transactions(token: String) async throws -> [HesabeTransaction] {
        // The token goes into the path, so it must not be able to change the path.
        guard !token.isEmpty, token.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...122).contains(byte) || (65...90).contains(byte)
        }) else {
            throw HesabeError.configuration("the session token is not alphanumeric")
        }
        let (data, response) = try await send(endpoint("api/transaction/enquire/\(token)", query: []))
        let envelope = try? JSONDecoder().decode(EnquiryEnvelope.self, from: data)

        // An unpaid session answers 404 {"status":false,"message":"Transaction not found"}.
        if response.statusCode == 404, envelope?.status == false { return [] }
        guard response.statusCode == 200, let envelope else {
            throw HesabeError.connection("Hesabe answered HTTP \(response.statusCode)")
        }
        return envelope.transactions
    }

    /// Asks Hesabe how a payment ended.
    ///
    /// - Parameter afterReturn: `true` when the customer came back from the payment
    ///   page, so a transaction is expected and the lookup is repeated for about ten
    ///   seconds while Hesabe records it. `false` when the customer closed the page:
    ///   one lookup, and no transaction means `.canceled`.
    public func settle(token: String, afterReturn: Bool) async -> PaymentResult {
        // Five lookups at most: Hesabe limits lookups to 30 a minute.
        let waits: [TimeInterval] = afterReturn ? [0, 1, 2, 3, 4] : [0]
        var unsettled: HesabeTransaction?
        var lastError = HesabeError.noTransaction

        for wait in waits {
            if wait > 0 { await pause(wait) }
            do {
                let attempts = try await transactions(token: token)
                if let paid = attempts.first(where: \.isPaid) { return .paid(paid) }
                if let failed = attempts.first(where: \.isFailed) { return .failed(failed) }
                unsettled = attempts.first ?? unsettled
                lastError = .noTransaction
            } catch let error as HesabeError {
                lastError = error
            } catch {
                lastError = .connection(error.localizedDescription)
            }
        }

        if let unsettled { return .pending(unsettled) }
        if !afterReturn, lastError == .noTransaction { return .canceled }
        return .unconfirmed(lastError)
    }

    // MARK: - Pending payments

    /// Settles payments this device started and never saw the end of: the app was
    /// closed during 3-D Secure, or the customer never came back from a banking app.
    /// Call it at launch. Each payment is reported once it is paid or failed.
    public func recoverPayments(in store: UserDefaults = .standard) async -> [PaymentResult] {
        HesabePendingPayments.prune(in: store)
        var settled: [PaymentResult] = []
        for pending in HesabePendingPayments.all(in: store) where pending.environment == environment {
            let result = await settle(token: pending.token, afterReturn: false)
            switch result {
            case .paid, .failed:
                HesabePendingPayments.resolve(pending.token, in: store)
                settled.append(result)
            case .pending, .canceled, .unconfirmed, .notStarted:
                continue
            }
        }
        return settled
    }

    // MARK: - Transport

    private func endpoint(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: environment.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func send(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            return try await transport(request)
        } catch let error as HesabeError {
            throw error
        } catch {
            throw HesabeError.connection(error.localizedDescription)
        }
    }

    private static let urlSession: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HesabeError.connection("the answer was not HTTP")
        }
        return (data, http)
    }

    private static let sleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Wire shapes

private struct DetailsEnvelope: Decodable {
    let status: Bool
    let message: String?
    let response: CheckoutDetails?
}

/// `{"status":true,"message":"Transaction found","data":{"data":[...]}}`
private struct EnquiryEnvelope: Decodable {
    let status: Bool
    let transactions: [HesabeTransaction]

    private enum CodingKeys: String, CodingKey { case status, data }
    private struct Payload: Decodable { let data: [HesabeTransaction]? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Bool.self, forKey: .status)
        if let payload = try? container.decode(Payload.self, forKey: .data), let list = payload.data {
            transactions = list
        } else if let single = try? container.decode(HesabeTransaction.self, forKey: .data) {
            transactions = [single]
        } else {
            transactions = []
        }
    }
}
