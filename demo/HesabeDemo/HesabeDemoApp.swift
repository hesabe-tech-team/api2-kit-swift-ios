import HesabeUI
import SwiftUI

@main
struct HesabeDemoApp: App {
    /// Payments an earlier launch started and never saw the end of.
    @State private var recovered: [PaymentResult] = []

    var body: some Scene {
        WindowGroup {
            CheckoutView()
                .task {
                    // A customer can pay in a banking app and never come back, and iOS
                    // can close the app during 3-D Secure. Ask Hesabe at every launch.
                    recovered = await HesabeClient(environment: Config.environment).recoverPayments()
                }
                .alert("An earlier payment was settled", isPresented: isShowingRecovered) {
                    Button("OK") { recovered = [] }
                } message: {
                    Text(recovered.map { Outcome($0).title }.joined(separator: ", "))
                }
        }
    }

    private var isShowingRecovered: Binding<Bool> {
        Binding(get: { !recovered.isEmpty }, set: { if !$0 { recovered = [] } })
    }
}
