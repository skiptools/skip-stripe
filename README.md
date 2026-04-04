# SkipStripe

This is a free [Skip](https://skip.dev) Swift/Kotlin framework that 
contains integration with the Stripe SDK's 'Mobile Payment Element
for [iOS](https://docs.stripe.com/sdks/ios)
and [Android](https://docs.stripe.com/sdks/android).

## Setup

To include this framework in your project, add the following
dependency to your `Package.swift` file:

```swift
let package = Package(
    name: "my-package",
    products: [
        .library(name: "MyProduct", targets: ["MyTarget"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.dev/skip-stripe.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(name: "MyTarget", dependencies: [
            .product(name: "SkipStripe", package: "skip-stripe")
        ])
    ]
)
```

### Usage

The API includes a `StripePaymentButton` which is created using a `StripePaymentConfiguration`.

For information on how to initialize the configuration object, see the Stripe documentation
for [iOS](https://docs.stripe.com/payments/accept-a-payment?platform=ios&ui=payment-sheet)
and [Android](https://docs.stripe.com/payments/accept-a-payment?platform=android&ui=payment-sheet).

The `SkiperStrip` sample app in this repository shows a complete Skip-to-native integration using:

- `skip-stripe/examples/PaymentSheetService.swift` – wrapper around Stripe's iOS payment sheet presenter.
- `skip-stripe/examples/StripePaymentService.swift` – shared service that creates payment intents, ephemeral keys, and SkipStripe configurations for Android.
- `skip-stripe/examples/ContentView.swift` – SwiftUI screen demonstrating both iOS and Android flows with `SimpleStripePaymentButton`.

```swift
import SkipStripe

struct PaymentButton: View {
    let paymentConfig = StripePaymentConfiguration(
        publishableKey: "PUBLISHABLE_KEY",
        merchantName: "Merchant, Inc.",
        customerID: "CUSTOMER_ID",
        ephemeralKeySecret: "EPHEMERAL_KEY_SECRET",
        clientSecret: "CLIENT_SECRET"
    )

    var body: some View {
        StripePaymentButton(configuration: paymentConfig, completion: paymentCompletion) {
            Text("Pay Now!")
        }
        .buttonStyle(.borderedProminent)
    }

    func paymentCompletion(result: StripePaymentResult) {
        switch result {
        case .completed:
            logger.log("Payment completed")
        case .canceled:
            logger.log("Payment canceled")
        case .failed(error: let error):
            logger.log("Payment error: \(error)")
        }
    }
}
```

## Usage Notes

Using Stripe for payments is subject to the policies of the
app marketplace that distributes the application.
Generally speaking, they can be used for purchases and subscriptions for
_non-digital_ goods, whereas digital purchses usually
use the native billing system of the hosting service.

For more details, see:

  - [Make in-app purchases in Android apps](https://support.google.com/googleplay/answer/1061913)
  - [Understanding Google Play’s Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818)
  - [Apple App Review Guidelines: In-App Purchase](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)
  - [Apple Human Interface Guidelines: In-app purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase)

For interfacing with the native in-app purchasing system on
the host device, consider using the
[SkipMarketplace](https://github.com/skiptools/skip-marketplace)
framework instead.

## Building

This project is a Swift Package Manager module that uses the
[Skip](https://skip.dev) plugin to build the package for both iOS and Android.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

## License

This software is licensed under the 
[Mozilla Public License 2.0](https://www.mozilla.org/MPL/).
