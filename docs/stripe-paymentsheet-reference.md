# Stripe PaymentSheet Integration Reference

This document contains key information from Stripe's official documentation for implementing PaymentSheet on iOS and Android.

## Overview

The PaymentSheet is Stripe's prebuilt payment UI for mobile apps. It handles:
- Displaying payment methods
- Collecting payment details
- Processing payments

## API Objects Required

1. **PaymentIntent** - Represents your intent to collect payment, tracks charge attempts and payment state
2. **Customer** (Optional) - For saving payment methods for future use
3. **CustomerSession** (Optional) - Grants SDK temporary scoped access to Customer data

## Server-side Endpoint

Your server needs an endpoint that:
1. Retrieves or creates a Customer
2. Creates a CustomerSession for the Customer
3. Creates a PaymentIntent with amount, currency, and customer
4. Returns to the app:
   - PaymentIntent's `client_secret`
   - CustomerSession's `client_secret`
   - Customer's `id`
   - Your publishable key

## iOS Integration (Swift/SwiftUI)

### UIKit Example

```swift
import UIKit
@_spi(CustomerSessionBetaAccess) import StripePaymentSheet

class CheckoutViewController: UIViewController {
    var paymentSheet: PaymentSheet?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Fetch from your backend
        var request = URLRequest(url: backendCheckoutUrl)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let customerId = json["customer"] as? String,
                  let customerSessionClientSecret = json["customerSessionClientSecret"] as? String,
                  let paymentIntentClientSecret = json["paymentIntent"] as? String,
                  let publishableKey = json["publishableKey"] as? String else { return }
            
            STPAPIClient.shared.publishableKey = publishableKey
            
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Example, Inc."
            configuration.customer = .init(id: customerId, customerSessionClientSecret: customerSessionClientSecret)
            configuration.allowsDelayedPaymentMethods = true
            
            self?.paymentSheet = PaymentSheet(
                paymentIntentClientSecret: paymentIntentClientSecret,
                configuration: configuration
            )
        }.resume()
    }
    
    func checkout() {
        paymentSheet?.present(from: self) { paymentResult in
            switch paymentResult {
            case .completed:
                print("Payment completed")
            case .canceled:
                print("Payment canceled")
            case .failed(let error):
                print("Payment failed: \(error)")
            }
        }
    }
}
```

### SwiftUI Example

```swift
import StripePaymentSheet
import SwiftUI

class CheckoutViewModel: ObservableObject {
    @Published var paymentSheet: PaymentSheet?
    @Published var paymentResult: PaymentSheetResult?
}
```

## Android Integration (Kotlin/Jetpack Compose)

```kotlin
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult

@Composable
fun App() {
    val paymentSheet = remember { PaymentSheet.Builder(::onPaymentSheetResult) }.build()
    val context = LocalContext.current
    var customerConfig by remember { mutableStateOf<PaymentSheet.CustomerConfiguration?>(null) }
    var paymentIntentClientSecret by remember { mutableStateOf<String?>(null) }
    
    LaunchedEffect(context) {
        // Fetch from your backend
        val networkResult = ...
        if (networkResult.isSuccess) {
            paymentIntentClientSecret = networkResult.paymentIntent
            customerConfig = PaymentSheet.CustomerConfiguration.createWithCustomerSession(
                id = networkResult.customer,
                clientSecret = networkResult.customerSessionClientSecret
            )
            PaymentConfiguration.init(context, networkResult.publishableKey)
        }
    }
}

private fun onPaymentSheetResult(paymentSheetResult: PaymentSheetResult) {
    when (paymentSheetResult) {
        is PaymentSheetResult.Completed -> println("Payment completed")
        is PaymentSheetResult.Canceled -> println("Payment canceled")
        is PaymentSheetResult.Failed -> println("Payment failed: ${paymentSheetResult.error}")
    }
}
```

### Present PaymentSheet

```kotlin
paymentSheet.presentWithPaymentIntent(
    paymentIntentClientSecret,
    PaymentSheet.Configuration.Builder("Example, Inc.")
        .customer(customerConfig)
        .allowsDelayedPaymentMethods(true)
        .build()
)
```

## PaymentSheetResult Values

- **Completed** - Payment succeeded
- **Canceled** - User dismissed the sheet
- **Failed(error)** - Payment failed with an error

## Resources

- iOS SDK: https://github.com/stripe/stripe-ios
- Android SDK: https://github.com/stripe/stripe-android
- Full iOS docs: https://docs.stripe.com/payments/accept-a-payment?payment-ui=mobile&platform=ios
- Full Android docs: https://docs.stripe.com/payments/accept-a-payment?payment-ui=mobile&platform=android
