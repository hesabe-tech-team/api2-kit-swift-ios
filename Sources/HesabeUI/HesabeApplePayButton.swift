#if canImport(UIKit)
import Hesabe
import PassKit
import SwiftUI
import UIKit

/// The wording on the Apple Pay button. Apple's names.
public enum HesabeApplePayButtonType: String, Sendable, Hashable {
    case plain
    case buy
    case checkout = "check-out"
    case book
    case subscribe
    case donate
    case order

    var passKit: PKPaymentButtonType {
        switch self {
        case .plain: .plain
        case .buy: .buy
        case .checkout: .checkout
        case .book: .book
        case .subscribe: .subscribe
        case .donate: .donate
        case .order: .order
        }
    }
}

/// The colours of the Apple Pay button. `automatic` is black in light mode and white
/// in dark mode.
public enum HesabeApplePayButtonStyle: String, Sendable, Hashable {
    case automatic
    case black
    case white
    case whiteOutline = "white-outline"

    var passKit: PKPaymentButtonStyle {
        switch self {
        case .automatic: .automatic
        case .black: .black
        case .white: .white
        case .whiteOutline: .whiteOutline
        }
    }
}

/// An Apple Pay button that sits in your own screen and pays one session.
///
/// The button is WebKit's, drawn by the hosted page in a web view the size of the
/// button, because Apple Pay through Hesabe starts on a registered web domain.
/// Everything around it is native: a stand-in while the page loads, a dimmed press,
/// a "Processing" state while Hesabe charges, a retry.
///
/// A session is single use. Give the button a new session, and a new `.id`, for the
/// next payment.
@MainActor
public struct HesabeApplePayButton: View {
    private let session: HesabeSession
    private let configuration: HesabeConfiguration
    private let method: PaymentMethod
    private let type: HesabeApplePayButtonType
    private let style: HesabeApplePayButtonStyle
    private let cornerRadius: CGFloat
    private let height: CGFloat
    private let strings: HesabeStrings
    private let onResult: @MainActor (PaymentResult) -> Void

    private enum Phase: Equatable { case loading, ready, processing, failed(String), done }

    @State private var phase = Phase.loading
    @State private var token: String?
    @State private var pageURL: URL?
    @State private var loads = 0

    /// - Parameters:
    ///   - session: a session your server created.
    ///   - method: the Apple Pay payment type enabled on your account: 11 is KNET
    ///     debit, 13 is KNET international, 9 is MPGS.
    ///   - onResult: called once, after Hesabe has been asked how the payment ended.
    ///     Closing the Apple Pay sheet is not a result: the button stays ready.
    public init(
        session: HesabeSession,
        configuration: HesabeConfiguration,
        method: PaymentMethod = .applePayKNETDebit,
        type: HesabeApplePayButtonType = .buy,
        style: HesabeApplePayButtonStyle = .automatic,
        cornerRadius: CGFloat = 8,
        height: CGFloat = 50,
        strings: HesabeStrings = .automatic,
        onResult: @escaping @MainActor (PaymentResult) -> Void
    ) {
        self.session = session
        self.configuration = configuration
        self.method = method
        self.type = type
        self.style = style
        self.cornerRadius = cornerRadius
        self.height = height
        self.strings = strings
        self.onResult = onResult
    }

    public var body: some View {
        Group {
            if case .failed(let message) = phase {
                // The same footprint as the button: a retry that says what went wrong.
                Button { loads += 1 } label: {
                    Label("\(strings.tryAgain) · \(message)", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(uiColor: .secondarySystemFill))
            } else {
                button
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: phase)
        .task(id: loads) { await load() }
    }

    private var button: some View {
        ZStack {
            // Under the web view until it has drawn, so the slot never shows a hole.
            NativeApplePayButton(type: type, style: style)
                .opacity(phase == .loading || phase == .done ? 0.5 : 0)

            if let pageURL, phase != .done {
                // Stays mounted while processing: the payment is a navigation inside it.
                ApplePayWebButton(
                    pageURL: pageURL, returnURLs: configuration.returnURLs,
                    cancelURL: Self.cancelURL(for: pageURL)
                ) { handle($0) }
                .id(pageURL)
                .opacity(phase == .ready ? 1 : 0)
                .allowsHitTesting(phase == .ready)
            }

            if phase == .processing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(strings.processing)
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemFill))
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        phase = .loading
        pageURL = nil
        guard let page = configuration.applePayPageURL else {
            phase = .failed("applePayPageURL is not set")
            return
        }
        do {
            let details = try await HesabeClient(environment: configuration.environment).details(for: session)
            guard !Task.isCancelled else { return }
            guard details.applePayMethods.contains(method) else {
                phase = .failed("Apple Pay type \(method.rawValue) is not enabled for this session")
                return
            }
            token = details.token
            pageURL = try Self.pageURL(
                page, session: session, environment: configuration.environment,
                method: method, type: type, style: style)
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    /// The hosted page with this payment's settings in the fragment. Browsers never
    /// send the fragment to a server, so the page is the same file for every payment.
    private static func pageURL(
        _ page: URL, session: HesabeSession, environment: HesabeEnvironment,
        method: PaymentMethod, type: HesabeApplePayButtonType, style: HesabeApplePayButtonStyle
    ) throws -> URL {
        var settings: [String: Any] = [
            "requestData": session.data,
            "environment": environment.rawValue,
            "paymentType": method.rawValue,
            "cancelUrl": cancelURL(for: page).absoluteString,
            "buttonType": type.rawValue,
        ]
        if style != .automatic { settings["buttonStyle"] = style.rawValue }
        if let language = Locale.preferredLanguages.first { settings["language"] = language }

        let json = try JSONSerialization.data(withJSONObject: settings, options: [.withoutEscapingSlashes])
        guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else {
            throw HesabeError.configuration("applePayPageURL is not a valid URL")
        }
        components.percentEncodedFragment = String(decoding: json, as: UTF8.self)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        guard let url = components.url, url.scheme == "https" else {
            throw HesabeError.configuration("applePayPageURL must be an https URL")
        }
        return url
    }

    /// Where the page goes when the customer closes the Apple Pay sheet. The app stops
    /// the navigation before it loads, so nothing has to exist there.
    private static func cancelURL(for page: URL) -> URL {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        let base = components?.url ?? page
        return base.deletingLastPathComponent().appendingPathComponent("hesabe-apple-pay-cancelled")
    }

    // MARK: - Events

    private func handle(_ event: ApplePayButtonEvent) {
        switch event {
        case .ready, .cancelled:
            phase = .ready
        case .failed(let message):
            phase = .failed(message)
        case .processing:
            phase = .processing
            guard let token else { return }
            HesabePendingPayments.track(PendingPayment(token: token, environment: configuration.environment))
            Task {
                // Hesabe redirects within seconds. If it never does, ask Hesabe and
                // stop spinning: by now the card may have been charged.
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                await settle()
            }
        case .returned, .lost:
            phase = .processing
            Task { await settle() }
        }
    }

    /// Reports once per session: the timeout and the return can both arrive.
    private func settle() async {
        guard phase == .processing, let token else { return }
        self.token = nil
        let result = await HesabeClient(environment: configuration.environment)
            .settle(token: token, afterReturn: true)
        switch result {
        case .paid, .cardSaved, .failed:
            HesabePendingPayments.resolve(token)
        case .pending, .unconfirmed, .canceled, .notStarted:
            break // left for recoverPayments() at the next launch
        }
        phase = .done
        onResult(result)
    }
}

/// PassKit's own button, used only as the stand-in while the web button loads: the
/// same artwork WebKit draws, so the swap is invisible. It takes no taps; the payment
/// belongs to the page, whose domain is registered with Apple.
private struct NativeApplePayButton: UIViewRepresentable {
    let type: HesabeApplePayButtonType
    let style: HesabeApplePayButtonStyle

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type.passKit, paymentButtonStyle: style.passKit)
        button.cornerRadius = 0 // the caller clips both buttons to one shape
        button.isUserInteractionEnabled = false
        return button
    }

    func updateUIView(_ button: PKPaymentButton, context: Context) {}
}
#endif
