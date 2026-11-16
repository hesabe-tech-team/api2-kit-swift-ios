#if canImport(UIKit)
import Hesabe
import UIKit

/// The ready-made checkout: a sheet that takes one session, lets the customer pay, asks
/// Hesabe how it ended, and returns that.
///
///     let sheet = HesabeCheckoutSheet(configuration: configuration)
///     let result = await sheet.present(session, methods: [.knet, .card], from: self)
@MainActor
public final class HesabeCheckoutSheet {
    private let configuration: HesabeConfiguration
    private let strings: HesabeStrings
    private let client: HesabeClient

    public init(configuration: HesabeConfiguration, strings: HesabeStrings = .automatic) {
        self.configuration = configuration
        self.strings = strings
        self.client = HesabeClient(environment: configuration.environment)
    }

    /// Presents the payment and returns once Hesabe has been asked how it ended.
    ///
    /// - Parameters:
    ///   - session: a session your server created. It is single use: after any result
    ///     except `.notStarted`, pay again with a new one.
    ///   - methods: the payment methods to offer. One opens that method directly.
    ///     Several show a native list of those enabled for the session. None opens
    ///     Hesabe's own page with every enabled method.
    ///   - presenter: the view controller on screen.
    @discardableResult
    public func present(
        _ session: HesabeSession,
        methods: [PaymentMethod] = [],
        from presenter: UIViewController
    ) async -> PaymentResult {
        guard presenter.presentedViewController == nil else {
            return .notStarted(.configuration("the presenting view controller is already presenting"))
        }

        let details: CheckoutDetails
        do {
            details = try await client.details(for: session)
        } catch let error as HesabeError {
            return .notStarted(error)
        } catch {
            return .notStarted(.connection(error.localizedDescription))
        }

        let offered = methods.filter(details.paymentMethods.contains)
        if !methods.isEmpty, offered.isEmpty {
            return .notStarted(.configuration("none of the requested payment methods is enabled for this session"))
        }

        let navigation = UINavigationController()
        navigation.modalPresentationStyle = .formSheet
        // The customer leaves through Cancel, so the end of the payment is always seen.
        navigation.isModalInPresentation = true

        var method: PaymentMethod? = offered.count == 1 ? offered[0] : nil
        if offered.count > 1 {
            let picker = MethodPickerViewController(
                methods: offered, amount: details.formattedAmount,
                title: configuration.merchantDisplayName ?? strings.chooseMethod,
                cancelTitle: strings.cancel)
            navigation.setViewControllers([picker], animated: false)
            method = await withCheckedContinuation { continuation in
                picker.onChoice = { continuation.resume(returning: $0) }
                presenter.present(navigation, animated: true)
            }
            guard method != nil else {
                await dismiss(navigation)
                return .canceled
            }
        }

        // Written down before the page opens: from here on money can move without
        // the app seeing the end of it.
        HesabePendingPayments.track(
            PendingPayment(token: details.token, environment: configuration.environment))

        let page = PaymentWebViewController(
            pageURL: client.paymentURL(for: session, method: method),
            returnURLs: configuration.returnURLs,
            title: configuration.merchantDisplayName ?? method?.displayName,
            cancelTitle: strings.cancel)
        let outcome: PaymentWebViewController.Outcome = await withCheckedContinuation { continuation in
            page.onOutcome = { continuation.resume(returning: $0) }
            if navigation.presentingViewController == nil {
                navigation.setViewControllers([page], animated: false)
                presenter.present(navigation, animated: true)
            } else {
                navigation.setViewControllers([page], animated: true)
            }
        }

        page.showConfirming(strings.confirming)
        var result: PaymentResult
        switch outcome {
        case .returned:
            result = await client.settle(token: details.token, afterReturn: true)
        case .canceled:
            result = await client.settle(token: details.token, afterReturn: false)
        case .failed(let error):
            result = await client.settle(token: details.token, afterReturn: false)
            // No transaction at Hesabe means the page failed before anything was paid.
            if result == .canceled { result = .notStarted(error) }
        }

        switch result {
        case .paid, .failed, .canceled, .notStarted:
            HesabePendingPayments.resolve(details.token)
        case .pending, .unconfirmed:
            break // left for recoverPayments() at the next launch
        }

        if let summary = strings.summary(of: result) {
            await page.showSettled(succeeded: summary.succeeded, message: summary.message)
        }
        await dismiss(navigation)
        return result
    }

    private func dismiss(_ navigation: UINavigationController) async {
        guard let presenting = navigation.presentingViewController else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presenting.dismiss(animated: true) { continuation.resume() }
        }
    }
}
#endif
