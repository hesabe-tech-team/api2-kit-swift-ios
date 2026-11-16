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

/// The two calls the app makes to your server. Any server that answers them works:
/// `demo/server/server.mjs` is one in about a hundred lines.
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

    private struct Failure: Decodable {
        let error: String
    }

    let baseURL: URL

    func createSession(quantity: Int) async throws -> (order: Order, session: HesabeSession) {
        let order: Order = try await post("session", ["quantity": quantity])
        do {
            return (order, try HesabeSession(data: order.data))
        } catch {
            throw BackendError.refused(error.localizedDescription)
        }
    }

    func confirm(token: String) async throws -> Confirmation {
        try await post("confirm", ["token": token])
    }

    private func post<Answer: Decodable>(_ path: String, _ body: [String: Any]) async throws -> Answer {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
