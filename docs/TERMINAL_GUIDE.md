# SkipStripe Terminal Integration Guide

A complete guide to enabling Stripe Terminal (in-person card payments) in your Skip Fuse app using the SkipStripe package. This covers both iOS and Android.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Package Setup](#package-setup)
4. [Backend Setup (Cloud Functions)](#backend-setup-cloud-functions)
5. [iOS Setup](#ios-setup)
6. [Android Setup](#android-setup)
7. [App Code: Token Provider](#app-code-token-provider)
8. [App Code: Initialize Terminal](#app-code-initialize-terminal)
9. [App Code: Create a Terminal Location](#app-code-create-a-terminal-location)
10. [App Code: Discover Readers](#app-code-discover-readers)
11. [App Code: Connect to a Reader](#app-code-connect-to-a-reader)
12. [App Code: Collect a Payment](#app-code-collect-a-payment)
13. [App Code: Disconnect](#app-code-disconnect)
14. [Reader Types & Discovery Methods](#reader-types--discovery-methods)
15. [Architecture Notes](#architecture-notes)
16. [Troubleshooting](#troubleshooting)

---

## Overview

SkipStripe wraps both the **Stripe iOS Terminal SDK** and the **Stripe Android Terminal SDK** behind a unified Swift API. Your app writes Swift once, and Skip Fuse transpiles the Android side to Kotlin automatically.

**What SkipStripe Terminal provides:**
- `StripeTerminalManager` — Singleton managing the full Terminal lifecycle
- `StripeTerminalReader` — Model for discovered/connected readers
- `StripeTerminalTokenProvider` — Protocol for fetching connection tokens
- `URLConnectionTokenProvider` — Built-in Android token provider using Firebase Auth
- `AuthenticatedCloudFunctionCaller` — Helper for calling Cloud Functions with auth
- Enums for connection status, payment status, discovery methods, device types

---

## Prerequisites

Before integrating Terminal, you need:

1. **Stripe Account** with Terminal enabled
   - Go to [Stripe Dashboard → Terminal](https://dashboard.stripe.com/terminal) to activate
2. **Stripe Connect** (if using connected accounts for marketplaces)
3. **Firebase Project** (if using Firebase Auth for backend authentication)
4. **Backend Server** (Cloud Functions or similar) to:
   - Create connection tokens
   - Create Terminal locations
   - Optionally: register readers, create payment intents
5. **Physical Stripe Reader** or use simulated readers for development

---

## Package Setup

### 1. Add SkipStripe to your Skip project

In your `Package.swift`, add the SkipStripe dependency:

```swift
dependencies: [
    .package(url: "https://github.com/nicka/skip-stripe.git", branch: "main"),
],
targets: [
    .target(
        name: "YourModule",
        dependencies: [
            .product(name: "SkipStripe", package: "skip-stripe"),
        ]
    ),
]
```

### 2. Configure skip.yml

SkipStripe uses `mode: transpiled` with `bridging: true`. Your app module that calls SkipStripe should be configured as `mode: native` (the default for Skip Fuse apps).

---

## Backend Setup (Cloud Functions)

You need at minimum a **connection token endpoint**. Here's a Firebase Cloud Functions example:

### Connection Token Endpoint

```javascript
// functions/index.js
const functions = require("firebase-functions");
const stripe = require("stripe")(functions.config().stripe.secret_key);

// HTTP endpoint for creating Terminal connection tokens
exports.createTerminalConnectionToken = functions.https.onRequest(async (req, res) => {
    // Verify Firebase Auth token from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ error: "Unauthorized" });
    }

    try {
        const token = await stripe.terminal.connectionTokens.create();
        res.json({ secret: token.secret });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});
```

### Create Terminal Location Endpoint

Locations are required for Bluetooth and Tap to Pay readers:

```javascript
exports.createTerminalLocationV1 = functions.https.onCall(async (data, context) => {
    const { shopId, displayName, line1, city, state, postalCode, country } = data;

    const location = await stripe.terminal.locations.create({
        display_name: displayName,
        address: {
            line1: line1,
            city: city,
            state: state,
            postal_code: postalCode,
            country: country || "US",
        },
    });

    // Optionally save location ID to your database (e.g., Firestore)
    // await admin.firestore().collection("shops").doc(shopId).update({
    //     terminalLocationId: location.id,
    // });

    return { locationId: location.id };
});
```

### For Stripe Connect (Direct Charges)

If you're using Stripe Connect, scope all Terminal operations to the connected account:

```javascript
const token = await stripe.terminal.connectionTokens.create({}, {
    stripeAccount: connectedAccountId,
});
```

---

## iOS Setup

### 1. Info.plist Permissions

Add the following to your iOS app's `Info.plist`:

```xml
<!-- Bluetooth (required for Bluetooth readers like M2, Chipper) -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to your card reader.</string>

<!-- Location (required by Stripe Terminal SDK) -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs your location to connect to nearby card readers.</string>

<!-- Local Network (required for Internet readers like S700, WisePOS E) -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app connects to Stripe readers on your local network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>

<!-- NFC (required for Tap to Pay on iPhone) -->
<key>NFCReaderUsageDescription</key>
<string>This app uses NFC to accept contactless payments.</string>
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```

### 2. Background Modes (optional, for Bluetooth)

If you want to maintain Bluetooth connections in the background:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

### 3. Capabilities

In Xcode, enable:
- **Near Field Communication Tag Reading** (for Tap to Pay)
- **Background Modes → Uses Bluetooth LE accessories** (optional)

---

## Android Setup

### 1. AndroidManifest.xml Permissions

Add to your Android manifest:

```xml
<!-- Bluetooth -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />

<!-- Location (required by Terminal SDK for Bluetooth) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- NFC (for Tap to Pay on Android) -->
<uses-permission android:name="android.permission.NFC" />

<!-- Internet -->
<uses-permission android:name="android.permission.INTERNET" />
```

### 2. Gradle Dependencies

The SkipStripe package includes the Stripe Terminal Android SDK dependency. Verify your `skip.yml` or `build.gradle` includes:

```groovy
implementation 'com.stripe:stripeterminal-core:4.+'
implementation 'com.stripe:stripeterminal-localmobile:4.+'  // For Tap to Pay
```

---

## App Code: Token Provider

### iOS Token Provider

On iOS, implement `StripeTerminalTokenProvider` in your app:

```swift
import SkipStripe
import FirebaseAuth

class MyTerminalService: StripeTerminalTokenProvider {
    static let shared = MyTerminalService()

    func fetchConnectionToken(completion: @escaping (String?, Error?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(nil, NSError(domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }

        user.getIDToken { idToken, error in
            guard let idToken = idToken else {
                completion(nil, error)
                return
            }

            let url = URL(string: "https://us-central1-YOUR-PROJECT.cloudfunctions.net/createTerminalConnectionToken")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = "{}".data(using: .utf8)

            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let secret = json["secret"] as? String else {
                    completion(nil, error ?? NSError(domain: "", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to get token"]))
                    return
                }
                completion(secret, nil)
            }.resume()
        }
    }
}
```

### Android Token Provider

On Android, use the built-in `URLConnectionTokenProvider`:

```swift
let provider = URLConnectionTokenProvider(
    backendURL: "https://us-central1-YOUR-PROJECT.cloudfunctions.net"
)
```

This automatically handles Firebase Auth token retrieval and calls your `/createTerminalConnectionToken` endpoint.

---

## App Code: Initialize Terminal

Call this once at app startup (e.g., in your main view's `.task` or `.onAppear`):

```swift
#if os(Android)
// Android: use the built-in URLConnectionTokenProvider
let provider = URLConnectionTokenProvider(
    backendURL: "https://us-central1-YOUR-PROJECT.cloudfunctions.net"
)
StripeTerminalManager.shared.initialize(tokenProvider: provider)
#else
// iOS: use your custom token provider
StripeTerminalManager.shared.initialize(tokenProvider: MyTerminalService.shared)
#endif
```

> **Important:** `initialize()` is a no-op if already called. Safe to call multiple times.

---

## App Code: Create a Terminal Location

A Terminal Location (address) is **required** before connecting to Bluetooth or Tap to Pay readers. Create one via your backend:

### iOS Example

```swift
func createLocation(shopId: String, address: String, city: String,
                    state: String, zip: String) async throws -> String {
    let user = Auth.auth().currentUser!
    let idToken = try await user.getIDToken()

    let url = URL(string: "https://us-central1-YOUR-PROJECT.cloudfunctions.net/createTerminalLocationV1")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = ["data": [
        "shopId": shopId,
        "displayName": "My Shop",
        "line1": address,
        "city": city,
        "state": state,
        "postalCode": zip,
        "country": "US"
    ]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, _) = try await URLSession.shared.data(for: request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let result = json["result"] as! [String: Any]
    return result["locationId"] as! String
}
```

### Android Example

Use the `AuthenticatedCloudFunctionCaller`:

```swift
AuthenticatedCloudFunctionCaller.shared.call(
    url: "https://us-central1-YOUR-PROJECT.cloudfunctions.net/createTerminalLocationV1",
    jsonBody: "{\"data\":{\"shopId\":\"\(shopId)\",\"displayName\":\"My Shop\",\"line1\":\"\(address)\",\"city\":\"\(city)\",\"state\":\"\(state)\",\"postalCode\":\"\(zip)\",\"country\":\"US\"}}"
) { success, response in
    // Parse the locationId from response
}
```

> **Tip:** Save the returned `locationId` (e.g., `tml_xxx`) to your database so you don't need to create a new location each time.

---

## App Code: Discover Readers

```swift
// Bluetooth readers (M2, Chipper 2X, WisePad 3)
StripeTerminalManager.shared.discoverReaders(method: .bluetoothScan)

// Internet readers (S700, WisePOS E) — must be on the same network
StripeTerminalManager.shared.discoverReaders(method: .internet)

// Tap to Pay (iPhone NFC or Android NFC)
StripeTerminalManager.shared.discoverReaders(method: .localMobile)

// For testing with simulated readers
StripeTerminalManager.shared.discoverReaders(method: .bluetoothScan, simulated: true)
```

**Access discovered readers:**

```swift
let readers = StripeTerminalManager.shared.discoveredReaders
// Each reader has: id, serialNumber, label, batteryLevel, isCharging, deviceType
```

**Cancel discovery:**

```swift
StripeTerminalManager.shared.cancelDiscovery()
```

---

## App Code: Connect to a Reader

```swift
let reader = StripeTerminalManager.shared.discoveredReaders[0]
let locationId = "tml_xxx" // Your Terminal Location ID

StripeTerminalManager.shared.connectReader(reader, locationId: locationId) { result in
    switch result {
    case .success(let connectedReader):
        print("Connected to: \(connectedReader.label ?? connectedReader.serialNumber)")
    case .failure(let error):
        print("Connection failed: \(error.localizedDescription)")
    }
}
```

> **Important:** `locationId` is required for Bluetooth and Tap to Pay readers. Internet readers may not require it.

**Check connection status:**

```swift
if StripeTerminalManager.shared.connectedReader != nil {
    // Reader is connected
}

// Or check the status enum
switch StripeTerminalManager.shared.connectionStatus {
case .connected: // Ready
case .connecting: // In progress
case .notConnected: // No reader
}
```

---

## App Code: Collect a Payment

```swift
let amountInCents = 1500  // $15.00
let currency = "usd"

StripeTerminalManager.shared.collectPayment(
    amount: amountInCents,
    currency: currency
) { result in
    switch result {
    case .success(let paymentIntentId):
        print("Payment successful: \(paymentIntentId)")
        // Save paymentIntentId to your order record
    case .failure(let error):
        print("Payment failed: \(error.localizedDescription)")
    }
}
```

**What happens under the hood:**

1. Creates a PaymentIntent on Stripe's servers
2. Prompts the customer to present their card on the reader
3. Confirms the PaymentIntent to finalize the charge
4. Returns the PaymentIntent ID on success

**Cancel an in-progress payment:**

```swift
StripeTerminalManager.shared.cancelPayment()
```

---

## App Code: Disconnect

```swift
StripeTerminalManager.shared.disconnectReader { error in
    if let error = error {
        print("Disconnect failed: \(error.localizedDescription)")
    } else {
        print("Reader disconnected")
    }
}
```

---

## Reader Types & Discovery Methods

| Reader | Type | Discovery Method | Connection | Location Required |
|--------|------|-----------------|------------|-------------------|
| Stripe M2 | Portable | `.bluetoothScan` | Bluetooth | Yes |
| Chipper 2X | Portable | `.bluetoothScan` | Bluetooth | Yes |
| WisePad 3 | Portable | `.bluetoothScan` | Bluetooth | Yes |
| Stripe S700 | Countertop | `.internet` | WiFi/Ethernet | No |
| WisePOS E | Countertop | `.internet` | WiFi/Ethernet | No |
| Tap to Pay (iPhone) | Built-in | `.localMobile` | NFC | Yes |
| Tap to Pay (Android) | Built-in | `.localMobile` | NFC | Yes |

---

## Architecture Notes

### How SkipStripe Works

SkipStripe is a **transpiled module** (`mode: transpiled`, `bridging: true` in `skip.yml`). This means:

1. **Swift code** is the source of truth for the API
2. On **iOS**, the Swift code compiles natively and calls the iOS Stripe SDK directly
3. On **Android**, Skip transpiles the Swift to **Kotlin**, and `SKIP INSERT` blocks inject raw Kotlin code to call the Android Stripe Terminal SDK
4. The **bridging** flag means the public API is automatically exposed back to native Swift via Skip Fuse

### Why SKIP INSERT?

The Stripe Terminal Android SDK uses Kotlin callback interfaces (`ConnectionTokenProvider`, `DiscoveryListener`, `ReaderCallback`, etc.) that cannot be expressed in transpiled Swift. The `SKIP INSERT` blocks inject raw Kotlin to implement these interfaces directly.

### Delegate Lifecycle (iOS)

The iOS `DiscoveryDelegate` (`ReaderDiscoveryDelegateWrapper`) must be stored as a **strong reference** on `StripeTerminalManager`. The Stripe SDK holds only a weak reference to it, so without strong storage, ARC deallocates it immediately and discovery callbacks are never received.

### Token Provider Pattern

The Terminal SDK automatically calls your `StripeTerminalTokenProvider.fetchConnectionToken()` whenever it needs a new connection token. You don't need to manage token refresh manually — just implement the provider and the SDK handles the rest.

---

## Troubleshooting

### Reader not discovered
- Ensure the reader is **powered on** and **charged**
- For Bluetooth: enable Bluetooth on the device and ensure Location permissions are granted
- For Internet readers: the reader and device must be on the **same network**
- Try using `simulated: true` to verify your code works with simulated readers first

### "Location ID is required" error
- Create a Terminal Location via your backend or the Stripe Dashboard
- Pass the `locationId` (e.g., `tml_xxx`) when calling `connectReader()`
- Save the location ID to your database so you can reuse it

### Discovery delegate not receiving callbacks (iOS)
- This was a known issue where the `DiscoveryDelegate` was deallocated by ARC
- Fixed by storing the delegate as a strong reference: `private var discoveryDelegate: ReaderDiscoveryDelegateWrapper?`
- If you're experiencing this, ensure you're using the latest SkipStripe version

### Connection fails immediately
- Verify your connection token endpoint is returning valid tokens
- Check that Firebase Auth is authenticated (the token provider needs a current user)
- Ensure your Stripe account has Terminal enabled

### Payment collection fails
- The reader must be connected before calling `collectPayment()`
- Ensure the amount is in the **smallest currency unit** (cents for USD)
- For Connect: ensure the PaymentIntent is scoped to the correct connected account

### Android: "User not authenticated" error
- The `URLConnectionTokenProvider` requires Firebase Auth to be signed in
- Ensure `FirebaseAuth.getInstance().currentUser` is not null before initializing Terminal

### Firmware updates during connection
- Some readers require firmware updates when connecting for the first time
- `StripeTerminalManager.isUpdatingFirmware` and `firmwareUpdateProgress` track this
- The update can take several minutes — show a progress indicator to the user

---

## Quick Reference

```swift
// 1. Initialize (once at app launch)
StripeTerminalManager.shared.initialize(tokenProvider: myProvider)

// 2. Discover readers
StripeTerminalManager.shared.discoverReaders(method: .bluetoothScan)

// 3. Connect to a reader
StripeTerminalManager.shared.connectReader(reader, locationId: "tml_xxx") { result in ... }

// 4. Collect payment
StripeTerminalManager.shared.collectPayment(amount: 1500, currency: "usd") { result in ... }

// 5. Disconnect
StripeTerminalManager.shared.disconnectReader { error in ... }
```

---

## License

SkipStripe is licensed under LGPL-3.0-only WITH LGPL-3.0-linking-exception.
