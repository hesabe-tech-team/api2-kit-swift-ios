import Foundation

/// Which Hesabe gateway a session belongs to. A session only works on the gateway
/// that created it.
public enum HesabeEnvironment: String, Sendable, Hashable, Codable {
    case sandbox
    case production

    /// The gateway's base URL.
    public var baseURL: URL {
        switch self {
        case .sandbox: URL(string: "https://sandbox.hesabe.com")!
        case .production: URL(string: "https://api.hesabe.com")!
        }
    }
}
