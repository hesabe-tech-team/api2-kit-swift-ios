#if canImport(UIKit)
import Hesabe
import SwiftUI
import UIKit
@preconcurrency import WebKit

/// What the button page tells the app. All of it is read off navigations: WebKit
/// switches Apple Pay off in a WKWebView as soon as the app injects script
/// (WKUserScript, evaluateJavaScript, callAsyncJavaScript), so there is no bridge.
enum ApplePayButtonEvent {
    /// The page is drawn; the button can be tapped.
    case ready
    /// The payment sheet was dismissed without paying.
    case cancelled
    /// The sheet authorised; the page left for Hesabe to take the payment.
    case processing
    /// Hesabe came back to a return URL. Look the payment up, don't trust the URL.
    case returned
    /// The page failed after the sheet: Hesabe may or may not have charged.
    case lost(String)
    /// The page never drew. Nothing was charged.
    case failed(String)
}

/// A web view that is nothing but the system Apple Pay button, drawn by WebKit on a
/// clear background. Give it a frame and clip it.
struct ApplePayWebButton: UIViewRepresentable {
    /// The hosted page with this payment's settings in its fragment.
    let pageURL: URL
    let returnURLs: ReturnURLs
    let cancelURL: URL
    let onEvent: @MainActor (ApplePayButtonEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(button: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // No cookies or cache carried between payments.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        let scrollView = webView.scrollView
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator

        // WebKit's button has no pressed state; a native one dims under the finger.
        let press = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delegate = context.coordinator
        webView.addGestureRecognizer(press)

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.button = self
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate,
        UIGestureRecognizerDelegate
    {
        var button: ApplePayWebButton
        private var isButtonDrawn = false
        private var hasLeft = false
        private var isDone = false

        init(button: ApplePayWebButton) {
            self.button = button
        }

        private func finish(_ event: ApplePayButtonEvent) {
            guard !isDone else { return }
            isDone = true
            button.onEvent(event)
        }

        private func isButtonPage(_ url: URL) -> Bool {
            Self.withoutFragment(url) == Self.withoutFragment(button.pageURL)
        }

        private static func withoutFragment(_ url: URL) -> URL? {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.url
        }

        // MARK: Navigation

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let frame = navigationAction.targetFrame else {
                return .cancel // a new window; the button opens none
            }
            guard frame.isMainFrame else { return .allow }

            if button.returnURLs.matches(url) {
                finish(.returned)
                return .cancel
            }
            if url.absoluteString.hasPrefix(button.cancelURL.absoluteString) {
                // The page stays where it is, so the same button can be tapped again.
                if !isDone { button.onEvent(.cancelled) }
                return .cancel
            }
            if isButtonPage(url), !isButtonDrawn { return .allow }
            guard url.scheme == "https", isButtonDrawn else { return .cancel }

            // Leaving the button page: Hesabe's script sends the authorised payment to
            // Hesabe as a top-level navigation, and Hesabe redirects to a return URL.
            if !hasLeft {
                hasLeft = true
                button.onEvent(.processing)
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
        ) {
            // The redirect to the return URL arrives here, not at the policy callback.
            guard let url = webView.url, button.returnURLs.matches(url) else { return }
            webView.stopLoading()
            finish(.returned)
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            guard navigationResponse.isForMainFrame else { return .allow }
            if let url = navigationResponse.response.url, button.returnURLs.matches(url) {
                finish(.returned)
                return .cancel
            }
            if !isButtonDrawn, let http = navigationResponse.response as? HTTPURLResponse,
                http.statusCode != 200
            {
                finish(.failed("The button page answered \(http.statusCode)."))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isButtonDrawn, !isDone else { return }
            isButtonDrawn = true
            button.onEvent(.ready)
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(hasLeft ? .lost("The page stopped mid-payment.") : .failed("The button page stopped."))
        }

        private func fail(_ error: Error) {
            let error = error as NSError
            // Both are the echo of a navigation this delegate cancelled itself.
            if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
            if error.domain == "WebKitErrorDomain", error.code == 102 { return }
            finish(hasLeft ? .lost(error.localizedDescription) : .failed(error.localizedDescription))
        }

        // MARK: A button, not a page

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }

        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let isDown = recognizer.state == .began || recognizer.state == .changed
            UIView.animate(
                withDuration: isDown ? 0.05 : 0.25, delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                view.alpha = isDown ? 0.6 : 1
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
#endif
