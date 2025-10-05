# SkipStripe

This is a free [Skip](https://skip.tools) Swift/Kotlin framework that 
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
        .package(url: "https://source.skip.tools/skip-stripe.git", "0.0.0"..<"2.0.0"),
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

## Building

This project is a free Swift Package Manager module that uses the
[Skip](https://skip.tools) plugin to transpile Swift into Kotlin.

Building the module requires that Skip be installed using
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
This will also install the necessary build prerequisites:
Kotlin, Gradle, and the Android build tools.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

## License

This software is licensed under the
[GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
with the following
[linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores) is permitted:

> This software is licensed under the LGPL3, included below.
> As a special exception to the GNU Lesser General Public License version 3
> ("LGPL3"), the copyright holders of this Library give you permission to
> convey to a third party a Combined Work that links statically or dynamically
> to this Library without providing any Minimal Corresponding Source or
> Minimal Application Code as set out in 4d or providing the installation
> information set out in section 4e, provided that you comply with the other
> provisions of LGPL3 and provided that you meet, for the Application the
> terms and conditions of the license(s) which apply to the Application.
> Except as stated in this special exception, the provisions of LGPL3 will
> continue to comply in full to this Library. If you modify this Library, you
> may apply this exception to your version of this Library, but you are not
> obliged to do so. If you do not wish to do so, delete this exception
> statement from your version. This exception does not (and cannot) modify any
> license terms which apply to the Application, with which you must still
> comply.
