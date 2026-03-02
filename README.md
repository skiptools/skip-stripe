# SkipStripe

A free [Skip](https://skip.dev) Swift/Kotlin framework that provides cross-platform integration with the Stripe SDK for both **online payments** (Payment Sheet) and **in-person payments** (Stripe Terminal) on [iOS](https://docs.stripe.com/sdks/ios) and [Android](https://docs.stripe.com/sdks/android).

## Features

- **Payment Sheet** — Present Stripe's pre-built payment UI for online purchases, subscriptions, and more. Supports Apple Pay (iOS) and Google Pay (Android).
- **Stripe Terminal** — Accept in-person card payments with physical Stripe readers (M2, Chipper 2X, WisePOS E, S700) and Tap to Pay on iPhone/Android.

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

---

## Payment Sheet (Online Payments)

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

---

## Stripe Terminal (In-Person Payments)

SkipStripe includes full support for [Stripe Terminal](https://stripe.com/terminal), enabling your app to accept in-person card payments with physical readers on both iOS and Android using a single Swift API.

### Supported Readers

| Reader | Type | Connection |
|--------|------|------------|
| Stripe M2 | Portable | Bluetooth |
| Chipper 2X | Portable | Bluetooth |
| WisePad 3 | Portable | Bluetooth |
| Stripe S700 | Countertop | WiFi / Ethernet |
| WisePOS E | Countertop | WiFi / Ethernet |
| Tap to Pay on iPhone | Built-in | NFC |
| Tap to Pay on Android | Built-in | NFC |

### Quick Start

```swift
import SkipStripe

// 1. Initialize the Terminal SDK (once at app launch)
StripeTerminalManager.shared.initialize(tokenProvider: myTokenProvider)

// 2. Discover nearby readers
StripeTerminalManager.shared.discoverReaders(method: .bluetoothScan)

// 3. Connect to a reader
let reader = StripeTerminalManager.shared.discoveredReaders[0]
StripeTerminalManager.shared.connectReader(reader, locationId: "tml_xxx") { result in
    switch result {
    case .success(let connected):
        print("Connected: \(connected.serialNumber)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// 4. Collect a payment ($15.00)
StripeTerminalManager.shared.collectPayment(amount: 1500, currency: "usd") { result in
    switch result {
    case .success(let paymentIntentId):
        print("Payment success: \(paymentIntentId)")
    case .failure(let error):
        print("Payment failed: \(error.localizedDescription)")
    }
}

// 5. Disconnect when done
StripeTerminalManager.shared.disconnectReader { error in }
```

### Terminal Prerequisites

1. **Stripe account** with [Terminal enabled](https://dashboard.stripe.com/terminal)
2. **Backend server** (e.g., Firebase Cloud Functions) to create connection tokens and Terminal locations
3. **A token provider** — implement `StripeTerminalTokenProvider` to fetch connection tokens from your backend. On Android, you can use the built-in `URLConnectionTokenProvider` which handles Firebase Auth automatically.

### Platform Setup

#### iOS

Add to your `Info.plist`:
- `NSBluetoothAlwaysUsageDescription` — for Bluetooth readers
- `NSLocationWhenInUseUsageDescription` — required by Stripe Terminal
- `NSLocalNetworkUsageDescription` + `NSBonjourServices` — for Internet readers
- `NFCReaderUsageDescription` — for Tap to Pay on iPhone

#### Android

Add to your `AndroidManifest.xml`:
- Bluetooth permissions: `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
- Location permissions: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- `NFC` permission for Tap to Pay
- `INTERNET` permission

### Key Types

| Type | Description |
|------|-------------|
| `StripeTerminalManager` | Singleton managing the full Terminal lifecycle (discovery, connection, payments) |
| `StripeTerminalReader` | Model representing a discovered or connected reader |
| `StripeTerminalTokenProvider` | Protocol you implement to fetch connection tokens from your backend |
| `URLConnectionTokenProvider` | Built-in Android token provider using Firebase Auth |
| `AuthenticatedCloudFunctionCaller` | Helper for calling Cloud Functions with Firebase Auth (Android) |
| `TerminalConnectionStatus` | Enum: `.notConnected`, `.connecting`, `.connected` |
| `TerminalPaymentStatus` | Enum: `.notReady`, `.ready`, `.waitingForInput`, `.processing` |
| `ReaderDiscoveryMethod` | Enum: `.bluetoothScan`, `.internet`, `.localMobile` |

### Full Documentation

For a complete step-by-step guide including backend setup, platform configuration, code examples, architecture notes, and troubleshooting, see the **[Terminal Integration Guide](docs/TERMINAL_GUIDE.md)**.

---

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

This project is a free Swift Package Manager module that uses the
[Skip](https://skip.dev) plugin to transpile Swift into Kotlin.

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
with a [linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores) is permitted.
