#if canImport(UIKit)
import Hesabe
import SwiftUI
import UIKit

public extension View {
    /// Presents the Hesabe checkout when `session` becomes non-nil, and sets it back
    /// to `nil` when the payment ends.
    ///
    ///     .hesabeCheckout(session: $session, configuration: configuration,
    ///                     methods: [.knet, .card]) { result in ... }
    func hesabeCheckout(
        session: Binding<HesabeSession?>,
        configuration: HesabeConfiguration,
        methods: [PaymentMethod] = [],
        strings: HesabeStrings = .automatic,
        onResult: @escaping @MainActor (PaymentResult) -> Void
    ) -> some View {
        background(
            HesabeCheckoutPresenter(session: session) { presenter, current in
                let sheet = HesabeCheckoutSheet(configuration: configuration, strings: strings)
                let result = await sheet.present(current, methods: methods, from: presenter)
                session.wrappedValue = nil
                onResult(result)
            }
        )
    }
}

/// SwiftUI cannot present a UIKit controller itself, so an invisible host view lends
/// the sheet a view controller to present from.
private struct HesabeCheckoutPresenter: UIViewControllerRepresentable {
    @Binding var session: HesabeSession?
    let run: @MainActor (UIViewController, HesabeSession) async -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let session, !context.coordinator.isRunning else { return }
        let coordinator = context.coordinator
        let run = run
        coordinator.isRunning = true
        Task { @MainActor in
            await run(controller, session)
            coordinator.isRunning = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var isRunning = false
    }
}
#endif
