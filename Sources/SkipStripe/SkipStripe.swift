// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
import SwiftUI

#if SKIP
// https://docs.stripe.com/payments/accept-a-payment?platform=android&ui=payment-sheet
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.PaymentSheetResultCallback
#elseif os(iOS)
// https://docs.stripe.com/payments/accept-a-payment?platform=ios&ui=payment-sheet&uikit-swiftui=swiftui
import Stripe
import StripeCore
import StripePayments
import StripePaymentsUI
import StripePaymentSheet
#endif

public struct StripePaymentConfiguration {
    public var merchantName: String
    public var customerID: String
    public var ephemeralKeySecret: String
    public var clientSecret: String
    public var allowsDelayedPaymentMethods: Bool?
    private static var paymentConfigurationInitialized = false

    public init(publishableKey: String? = nil, merchantName: String, customerID: String, ephemeralKeySecret: String, clientSecret: String) {
        self.merchantName = merchantName
        self.customerID = customerID
        self.ephemeralKeySecret = ephemeralKeySecret
        self.clientSecret = clientSecret

        // if we passed the publishable key here, attempt to perform the Stripe setup
        if let publishableKey {
            Self.initializePaymentConfig(key: publishableKey)
        }
    }

    public static func initializePaymentConfig(key publishableKey: String) {
        // only initialize the Stripe SDK once
        if Self.paymentConfigurationInitialized { return }
        paymentConfigurationInitialized = true

        #if SKIP
        let context = ProcessInfo.processInfo.androidContext

        // this needs to be done with a "SKIP INSERT" becuase otherwise Skip will miinterpret it as a construtor
        // SKIP INSERT: PaymentConfiguration.init(context, publishableKey)
        #elseif os(iOS)
        STPAPIClient.shared.publishableKey = publishableKey
        #else
        fatalError("Unsupported platform")
        #endif
    }
}

public enum StripePaymentResult {
    case completed
    case canceled
    case failed(error: Error)
}

/// A button that will present the Stripe payment sheet for the given configuration
public struct StripePaymentButton<Label: View>: View {
    let configuration: StripePaymentConfiguration
    let completion: (StripePaymentResult) -> Void
    let buttonLabel: () -> Label

    public init(configuration: StripePaymentConfiguration, completion: @escaping (StripePaymentResult) -> Void, @ViewBuilder buttonLabel: @escaping () -> Label) {
        self.configuration = configuration
        self.completion = completion
        self.buttonLabel = buttonLabel
    }

    public var body: some View {
        #if SKIP
        let customerConfig = PaymentSheet.CustomerConfiguration(id: configuration.customerID, ephemeralKeySecret: configuration.ephemeralKeySecret)

        var cfgbuilder = PaymentSheet.Configuration.Builder(merchantDisplayName: configuration.merchantName)
        cfgbuilder = cfgbuilder.customer(customerConfig)
        if let allowsDelayedPaymentMethods = configuration.allowsDelayedPaymentMethods {
            cfgbuilder = cfgbuilder.allowsDelayedPaymentMethods(allowsDelayedPaymentMethods)
        }
        let paymentConfig = cfgbuilder.build()

        let callback = completion
        var builder = PaymentSheet.Builder({ result in
            // translate PaymentSheetResult into StripePaymentResult
            switch result {
            case PaymentSheetResult.Completed:
                self.completion(StripePaymentResult.completed)
            case PaymentSheetResult.Canceled:
                self.completion(StripePaymentResult.canceled)
            default: // i.e.: case PaymentSheetResult.Failed:
                if result is PaymentSheetResult.Failed {
                    self.completion(StripePaymentResult.failed(error: ErrorException(result.error)))
                }
            }
        })
        let paymentSheet = builder.build()

        Button(action: {
            paymentSheet.presentWithPaymentIntent(configuration.clientSecret, paymentConfig)
        }, label: buttonLabel)

        #elseif os(iOS)
        let customerConfig = PaymentSheet.CustomerConfiguration(id: configuration.customerID, ephemeralKeySecret: configuration.ephemeralKeySecret)

        var paymentConfig = PaymentSheet.Configuration()
        paymentConfig.customer = customerConfig
        paymentConfig.merchantDisplayName = configuration.merchantName
        if let allowsDelayedPaymentMethods = configuration.allowsDelayedPaymentMethods {
            paymentConfig.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
        }

        let paymentSheet = PaymentSheet(paymentIntentClientSecret: configuration.clientSecret, configuration: paymentConfig)

        return PaymentSheet.PaymentButton(paymentSheet: paymentSheet, onCompletion: { result in
            // translate PaymentSheetResult into StripePaymentResult
            switch result {
            case .completed:
                self.completion(StripePaymentResult.completed)
            case .canceled:
                self.completion(StripePaymentResult.canceled)
            case .failed(error: let error):
                self.completion(StripePaymentResult.failed(error: error))
            }
        }, content: buttonLabel)
        #else
        fatalError("Unsupported platform")
        #endif
    }
}

#endif
