// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hesabe",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        // The checkout sheet and the Apple Pay button. Re-exports `Hesabe`.
        .library(name: "HesabeUI", targets: ["HesabeUI"]),
        // Sessions, lookups and results with no UI, for apps that draw their own.
        .library(name: "Hesabe", targets: ["Hesabe"]),
    ],
    targets: [
        // Foundation only. Holds no merchant keys and does no encryption.
        .target(name: "Hesabe"),

        // UIKit, SwiftUI and WebKit. Compiles to nothing on platforms without UIKit.
        .target(name: "HesabeUI", dependencies: ["Hesabe"]),

        .testTarget(
            name: "HesabeTests",
            dependencies: ["Hesabe"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
