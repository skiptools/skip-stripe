// swift-tools-version: 6.0
// This is a Skip (https://skip.tools) package.
import PackageDescription

let package = Package(
    name: "skiper-stripe",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkiperStrip", type: .dynamic, targets: ["SkiperStrip"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.6.27"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-firebase.git", "0.10.0"..<"2.0.0"),
        .package(url: "https://source.skip.tools/skip-stripe.git", from: "0.0.1")
    ],
    targets: [
        .target(name: "SkiperStrip", dependencies: [
            .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
            .product(name: "SkipFirebaseMessaging", package: "skip-firebase"),
            .product(name: "SkipFirebaseFirestore", package: "skip-firebase"),
            .product(name: "SkipFirebaseStorage", package: "skip-firebase"),
            .product(name: "SkipFirebaseAnalytics", package: "skip-firebase"),
            .product(name: "SkipFirebaseAuth", package: "skip-firebase"),
            .product(name: "SkipStripe", package: "skip-stripe")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
