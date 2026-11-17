import Foundation
import HesabeUI

/// What can go wrong talking to your own server.
enum BackendError: LocalizedError {
    case unreachable(String)
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let message): "Could not reach the server: \(message)"
        case .refused(let message): "The server said: \(message)"
        }
    }
}

/// The calls the app makes to your server. Any server that answers them works:
/// `demo/server/server.mjs` is one in about two hundred lines.
struct Backend {
    /// A session your server created with Hesabe's Checkout API.
    struct Order: Decodable {
        /// `response.data` from the Checkout API. The SDK takes this.
        let data: String
        let token: String
        let reference: String
    }

    /// What your server found when it asked Hesabe about a payment itself.
    struct Confirmation: Decodable {
        let paid: Bool
        let status: String
    }

    /// Hesabe's answer to your server charging a saved card.
    struct Charge: Decodable {
        let paid: Bool
        let status: String
        let amount: String?
        let reference: String?
        let message: String?
    }

    private struct CardList: Decodable {
        let cards: [HesabeSavedCard]
    }

    private struct Removal: Decodable {
        let removed: Bool
    }

    private struct Failure: Decodable {
        let error: String
    }

    let baseURL: URL

    // MARK: - Payments

    /// - Parameter saveCard: asks your server to put the customer on the session, so
    ///   Hesabe's card form offers to save the card.
    func createSession(quantity: Int, saveCard: Bool = false) async throws -> HesabeSession {
        let order: Order = try await send("POST", "session", ["quantity": quantity, "saveCard": saveCard])
        return try session(from: order)
    }

    func confirm(token: String) async throws -> Confirmation {
        try await send("POST", "confirm", ["token": token])
    }

    // MARK: - Saved cards

    /// A session that saves a card and charges nothing.
    func createCardSession() async throws -> HesabeSession {
        let order: Order = try await send("POST", "cards/session", [:])
        return try session(from: order)
    }

    func savedCards() async throws -> [HesabeSavedCard] {
        let list: CardList = try await send("GET", "cards", nil)
        return list.cards
    }

    /// Your server charges the card. There is no page and no 3-D Secure.
    func charge(_ card: HesabeSavedCard, quantity: Int) async throws -> Charge {
        try await send("POST", "cards/charge", ["cardId": card.id, "quantity": quantity])
    }

    func remove(_ card: HesabeSavedCard) async throws {
        let _: Removal = try await send("POST", "cards/remove", ["cardId": card.id])
    }

    // MARK: - Transport

    private func session(from order: Order) throws -> HesabeSession {
        do {
            return try HesabeSession(data: order.data)
        } catch {
            throw BackendError.refused(error.localizedDescription)
        }
    }

    private func send<Answer: Decodable>(
        _ method: String, _ path: String, _ body: [String: Any]?
    ) async throws -> Answer {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 60
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendError.unreachable(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw BackendError.refused(message ?? "an unexpected answer")
        }
        do {
            return try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw BackendError.refused("an answer the app could not read")
        }
    }
}
