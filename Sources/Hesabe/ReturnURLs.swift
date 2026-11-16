import Foundation

/// The `responseUrl` and `failureUrl` your server puts in every Checkout API request.
///
/// Hesabe sends the customer to one of them when the payment ends. The SDK stops that
/// navigation before it loads, so neither has to exist, and both may be the same URL.
/// Which one was reached proves nothing: the outcome comes from a lookup.
public struct ReturnURLs: Sendable, Hashable {
    public let success: URL
    public let failure: URL

    public init(success: URL, failure: URL) {
        self.success = success
        self.failure = failure
    }

    /// One URL used as both `responseUrl` and `failureUrl`.
    public init(_ url: URL) {
        self.init(success: url, failure: url)
    }

    /// True when `url` is one of the two, whatever query Hesabe added to it.
    public func matches(_ url: URL) -> Bool {
        Self.same(url, success) || Self.same(url, failure)
    }

    private static func same(_ candidate: URL, _ target: URL) -> Bool {
        guard let a = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              let b = URLComponents(url: target, resolvingAgainstBaseURL: false)
        else { return false }
        return a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && a.port == b.port
            && normalized(a.path) == normalized(b.path)
    }

    private static func normalized(_ path: String) -> String {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.isEmpty ? "/" : trimmed
    }
}
