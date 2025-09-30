// swift-tools-version: 5.9
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "skip-stripe",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkipStripe", type: .dynamic, targets: ["SkipStripe"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.27"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/stripe/stripe-ios.git", from: "24.24.1")
    ],
    targets: [
        .target(name: "SkipStripe", dependencies: [
            .product(name: "SkipUI", package: "skip-ui"),
            .product(name: "Stripe", package: "stripe-ios", condition: .when(platforms: [.iOS])),
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SkipStripeTests", dependencies: [
            "SkipStripe",
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
