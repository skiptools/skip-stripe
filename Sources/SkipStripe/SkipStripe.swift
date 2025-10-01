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
import PassKit
#endif

/// The configuration for a `StripePaymentButton`.
///
/// This vends an
/// iOS [`PaymentSheet.Configuration`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/configuration-swift.struct)
/// and
/// Android [`com.stripe.android.paymentsheet.PaymentSheet.Configuration`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-configuration/index.html)
public struct StripePaymentConfiguration {
    public var merchantName: String
    public var customerID: String
    public var ephemeralKeySecret: String
    public var clientSecret: String
    public var primaryButtonLabel: String?
    public var allowsDelayedPaymentMethods: Bool?
    public var allowsPaymentMethodsRequiringShippingAddress: Bool?
    public var defaultBillingDetails: BillingDetails?
    public var shippingDetails: AddressDetails?
    public var preferredNetworks: [CardBrand]?

    // https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/applepayconfiguration
    public var applePay: ApplePayConfiguration?

    // TODO: https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-google-pay-configuration/index.html
    public var googlePay: GooglePayConfiguration?

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

    /// A card brand.
    ///
    /// This is a wrapper around the iOS [`StripePaymentSheet.STPCardBrand`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/stpcardbrand) and Android [`com.stripe.android.model.CardBrand`](https://stripe.dev/stripe-android/payments-model/com.stripe.android.model/-card-brand/index.html)
    public enum CardBrand: Equatable {
        /// JCB card
        case JCB
        /// American Express card
        case amex
        /// Cartes Bancaires
        case cartesBancaires
        /// Diners Club card
        case dinersClub
        /// Discover card
        case discover
        /// Mastercard card
        case mastercard
        /// UnionPay card
        case unionPay
        /// An unknown card brand type
        case unknown
        /// Visa card
        case visa

        #if SKIP || os(iOS)
        #if os(iOS)
        typealias PlatformCardBrand = StripePaymentSheet.STPCardBrand
        #elseif SKIP
        typealias PlatformCardBrand = com.stripe.android.model.CardBrand
        #endif

        var platformCardbrand: PlatformCardBrand {
            #if SKIP
            switch self {
            case .JCB: return PlatformCardBrand.JCB
            case .amex: return PlatformCardBrand.AmericanExpress
            case .cartesBancaires: return PlatformCardBrand.CartesBancaires
            case .dinersClub: return PlatformCardBrand.DinersClub
            case .discover: return PlatformCardBrand.Discover
            case .mastercard: return PlatformCardBrand.MasterCard
            case .unionPay: return PlatformCardBrand.UnionPay
            case .unknown: return PlatformCardBrand.Unknown
            case .visa: return PlatformCardBrand.Visa
            }
            #else
            switch self {
            case .JCB: return PlatformCardBrand.JCB
            case .amex: return PlatformCardBrand.amex
            case .cartesBancaires: return PlatformCardBrand.cartesBancaires
            case .dinersClub: return PlatformCardBrand.dinersClub
            case .discover: return PlatformCardBrand.discover
            case .mastercard: return PlatformCardBrand.mastercard
            case .unionPay: return PlatformCardBrand.unionPay
            case .unknown: return PlatformCardBrand.unknown
            case .visa: return PlatformCardBrand.visa
            }
            #endif
        }
        #endif

    }

    /// Address details.
    ///
    /// This wrapper for
    /// [Address Collection](https://docs.stripe.com/payments/mobile/collect-addresses) around the
    /// iOS [`AddressViewController.AddressDetails`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/addressviewcontroller/addressdetails)
    /// and
    /// Android [`com.stripe.android.paymentsheet.addresselement.AddressDetails`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet.addresselement/-address-details/index.html)
    public struct AddressDetails: Equatable {
        public var address: Address
        public var name: String?
        public var phone: String?
        public var isCheckboxSelected: Bool?

        public init(address: Address, name: String? = nil, phone: String? = nil, isCheckboxSelected: Bool? = nil) {
            self.address = address
            self.name = name
            self.phone = phone
            self.isCheckboxSelected = isCheckboxSelected
        }

        #if SKIP || os(iOS)
        #if SKIP
        typealias PlatformAddressDetails = com.stripe.android.paymentsheet.addresselement.AddressDetails
        #else
        typealias PlatformAddressDetails = AddressViewController.AddressDetails
        #endif

        var platformShippingDetails: PlatformAddressDetails {
            #if SKIP
            PlatformAddressDetails(name: name, address: address.platformAddress, phoneNumber: phone, isCheckboxSelected: isCheckboxSelected)
            #else
            PlatformAddressDetails(address: AddressViewController.AddressDetails.Address(city: address.city, country: address.country, line1: address.line1, line2: address.line2, postalCode: address.postalCode, state: address.state), name: name, phone: phone, isCheckboxSelected: isCheckboxSelected)
            #endif
        }
        #endif
    }

    /// Billing details.
    ///
    /// This is a wrapper around the iOS [`PaymentSheet.BillingDetails`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/billingdetails) and Android [`com.stripe.android.paymentsheet.PaymentSheet.BillingDetails`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-billing-details/index.html)
    public struct BillingDetails: Equatable {
        public var address: Address
        public var email: String?
        public var name: String?
        public var phone: String?

        public init(address: Address, email: String? = nil, name: String? = nil, phone: String? = nil) {
            self.address = address
            self.email = email
            self.name = name
            self.phone = phone
        }

        #if SKIP || os(iOS)
        typealias PlatformBillingDetails = PaymentSheet.BillingDetails
        var platformBillingDetails: PlatformBillingDetails {
            PaymentSheet.BillingDetails(address: address.platformAddress, email: email, name: name, phone: phone)
        }
        #endif
    }

    /// An address.
    ///
    /// This is a wrapper around the iOS [`PaymentSheet.Address`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/address) and Android [`com.stripe.android.paymentsheet.PaymentSheet.Address`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-address/index.html)
    public struct Address: Equatable {
        public var city: String?
        public var country: String
        public var line1: String
        public var line2: String?
        public var postalCode: String?
        public var state: String?

        public init(city: String? = nil, country: String, line1: String, line2: String? = nil, postalCode: String? = nil, state: String? = nil) {
            self.city = city
            self.country = country
            self.line1 = line1
            self.line2 = line2
            self.postalCode = postalCode
            self.state = state
        }

        #if SKIP || os(iOS)
        typealias PlatformAddress = PaymentSheet.Address

        var platformAddress: PlatformAddress {
            PaymentSheet.Address(city: city, country: country, line1: line1, line2: line2, postalCode: postalCode, state: state)
        }
        #endif
    }

    /// [`PaymentSheet.ApplePayConfiguration`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/applepayconfiguration)
    public struct ApplePayConfiguration: Equatable {
        public var merchantId: String
        public var merchantCountryCode: String
        public var buttonType: ButtonType
        public var paymentSummaryItems: [SummaryItem]?

        // public var customHandlers: PaymentSheet.ApplePayConfiguration.Handlers? // TODO

        public init(merchantId: String, merchantCountryCode: String, buttonType: ButtonType, paymentSummaryItems: [SummaryItem]? = nil) {
            self.merchantId = merchantId
            self.merchantCountryCode = merchantCountryCode
            self.buttonType = buttonType
            self.paymentSummaryItems = paymentSummaryItems
        }

        #if os(iOS)
        var platformApplePay: PaymentSheet.ApplePayConfiguration {
            PaymentSheet.ApplePayConfiguration(merchantId: merchantId, merchantCountryCode: merchantCountryCode, buttonType: buttonType.platformButtonType, paymentSummaryItems: paymentSummaryItems?.map(\.platformSummaryItem), customHandlers: nil)
        }
        #endif

        public enum ButtonType: Equatable {
            case plain
            case buy
            case setUp
            case inStore
            case donate
            case checkout
            case book
            case subscribe
            case reload
            case addMoney
            case topUp
            case order
            case rent
            case support
            case contribute
            case tip
            case `continue`

            #if os(iOS)
            var platformButtonType: PKPaymentButtonType {
                switch self {
                case .plain: return PKPaymentButtonType.plain
                case .buy: return PKPaymentButtonType.buy
                case .setUp: return PKPaymentButtonType.setUp
                case .inStore: return PKPaymentButtonType.inStore
                case .donate: return PKPaymentButtonType.donate
                case .checkout: return PKPaymentButtonType.checkout
                case .book: return PKPaymentButtonType.book
                case .subscribe: return PKPaymentButtonType.subscribe
                case .reload: return PKPaymentButtonType.reload
                case .addMoney: return PKPaymentButtonType.addMoney
                case .topUp: return PKPaymentButtonType.topUp
                case .order: return PKPaymentButtonType.order
                case .rent: return PKPaymentButtonType.rent
                case .support: return PKPaymentButtonType.support
                case .contribute: return PKPaymentButtonType.contribute
                case .tip: return PKPaymentButtonType.tip
                case .continue: return PKPaymentButtonType.continue
                }
            }
            #endif
        }

        public struct SummaryItem: Equatable {
            public let label: String
            public let amount: Decimal
            public let pending: Bool

            public init(label: String, amount: Decimal, pending: Bool) {
                self.label = label
                self.amount = amount
                self.pending = pending
            }

            #if os(iOS)
            var platformSummaryItem: PKPaymentSummaryItem {
                PKPaymentSummaryItem(label: label, amount: amount as NSDecimalNumber, type: pending ? .pending : .final)
            }
            #endif
        }
    }

    /// [`com.stripe.android.paymentsheet.PaymentSheet.GooglePayConfiguration`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-google-pay-configuration/index.html)
    public struct GooglePayConfiguration: Equatable {
        public var production: Bool = true
        public var countryCode: String
        public var currencyCode: String? = nil
        public var amount: Int64? = nil
        public var label: String? = nil
        public var buttonType: ButtonType = ButtonType.pay

        public init(production: Bool = true, countryCode: String, currencyCode: String? = nil, amount: Int64? = nil, label: String? = nil, buttonType: ButtonType) {
            self.production = production
            self.countryCode = countryCode
            self.currencyCode = currencyCode
            self.amount = amount
            self.label = label
            self.buttonType = buttonType
        }

        #if SKIP
        var platformGooglePay: PaymentSheet.GooglePayConfiguration {
            PaymentSheet.GooglePayConfiguration(environment: production ? PaymentSheet.GooglePayConfiguration.Environment.Production : PaymentSheet.GooglePayConfiguration.Environment.Test, countryCode: countryCode, currencyCode: currencyCode, amount: amount, label: label, buttonType: buttonType.platformButtonType)
        }
        #endif

        public enum ButtonType: Equatable {
            /// Displays "Buy with" alongside the Google Pay logo.
            case buy
            /// Displays "Book with" alongside the Google Pay logo.
            case book
            /// Displays "Checkout with" alongside the Google Pay logo.
            case checkout
            /// Displays "Donate with" alongside the Google Pay logo.
            case donate
            /// Displays "Order with" alongside the Google Pay logo.
            case order
            /// Displays "Pay with" alongside the Google Pay logo.
            case pay
            /// Displays "Subscribe with" alongside the Google Pay logo.
            case subscribe
            /// Displays only the Google Pay logo.
            case plain

            #if SKIP
            var platformButtonType: PaymentSheet.GooglePayConfiguration.ButtonType {
                switch self {
                case .buy: return PaymentSheet.GooglePayConfiguration.ButtonType.Buy
                case .book: return PaymentSheet.GooglePayConfiguration.ButtonType.Book
                case .checkout: return PaymentSheet.GooglePayConfiguration.ButtonType.Checkout
                case .donate: return PaymentSheet.GooglePayConfiguration.ButtonType.Donate
                case .order: return PaymentSheet.GooglePayConfiguration.ButtonType.Order
                case .pay: return PaymentSheet.GooglePayConfiguration.ButtonType.Pay
                case .subscribe: return PaymentSheet.GooglePayConfiguration.ButtonType.Subscribe
                case .plain: return PaymentSheet.GooglePayConfiguration.ButtonType.Plain
                }
            }
            #endif
        }
    }
}

/// The result of a `StripePaymentButton` payment action.
public enum StripePaymentResult {
    case completed
    case canceled
    case failed(error: Error)
}

/// A button that will present the Stripe payment sheet for the given configuration
// SKIP @nobridge // SkipFuse does not currently view wrappers so we need to use a `SimpleStripePaymentButton`
public struct StripePaymentButton<Label>: View where Label : View {
    let configuration: StripePaymentConfiguration
    let completion: (StripePaymentResult) -> Void
    let buttonLabel: () -> Label

    public init(configuration: StripePaymentConfiguration, completion: @escaping (StripePaymentResult) -> Void, @ViewBuilder buttonLabel: @escaping () -> Label) {
        self.configuration = configuration
        self.completion = completion
        self.buttonLabel = buttonLabel
    }

    public var body: some View {
        #if !SKIP && !os(iOS)
        fatalError("Unsupported platform")
        #else
        let customerConfig = PaymentSheet.CustomerConfiguration(id: configuration.customerID, ephemeralKeySecret: configuration.ephemeralKeySecret)

        #if !SKIP
        var paymentConfig = PaymentSheet.Configuration()
        paymentConfig.customer = customerConfig
        paymentConfig.merchantDisplayName = configuration.merchantName

        if let applePay = configuration.applePay {
            paymentConfig.applePay = applePay.platformApplePay
        }
        if let preferredNetworks = configuration.preferredNetworks {
            paymentConfig.preferredNetworks = preferredNetworks.map(\.platformCardbrand)
        }
        if let primaryButtonLabel = configuration.primaryButtonLabel {
            paymentConfig.primaryButtonLabel = primaryButtonLabel
        }
        if let allowsDelayedPaymentMethods = configuration.allowsDelayedPaymentMethods {
            paymentConfig.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
        }
        if let allowsPaymentMethodsRequiringShippingAddress = configuration.allowsPaymentMethodsRequiringShippingAddress {
            paymentConfig.allowsPaymentMethodsRequiringShippingAddress = allowsPaymentMethodsRequiringShippingAddress
        }
        if let defaultBillingDetails = configuration.defaultBillingDetails {
            paymentConfig.defaultBillingDetails = defaultBillingDetails.platformBillingDetails
        }
        if let shippingDetails = configuration.shippingDetails {
            paymentConfig.shippingDetails = { shippingDetails.platformShippingDetails }
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
        var cfgbuilder = PaymentSheet.Configuration.Builder(merchantDisplayName: configuration.merchantName)
        cfgbuilder = cfgbuilder.customer(customerConfig)
        if let googlePay = configuration.googlePay {
            cfgbuilder = cfgbuilder.googlePay(googlePay.platformGooglePay)
        }
        if let preferredNetworks = configuration.preferredNetworks {
            cfgbuilder = cfgbuilder.preferredNetworks(preferredNetworks.map(\.platformCardbrand).toList())
        }
        if let primaryButtonLabel = configuration.primaryButtonLabel {
            cfgbuilder = cfgbuilder.primaryButtonLabel(primaryButtonLabel)
        }
        if let allowsDelayedPaymentMethods = configuration.allowsDelayedPaymentMethods {
            cfgbuilder = cfgbuilder.allowsDelayedPaymentMethods(allowsDelayedPaymentMethods)
        }
        if let allowsPaymentMethodsRequiringShippingAddress = configuration.allowsPaymentMethodsRequiringShippingAddress {
            cfgbuilder = cfgbuilder.allowsPaymentMethodsRequiringShippingAddress(allowsPaymentMethodsRequiringShippingAddress)
        }
        if let defaultBillingDetails = configuration.defaultBillingDetails {
            cfgbuilder = cfgbuilder.defaultBillingDetails(defaultBillingDetails.platformBillingDetails)
        }
        if let shippingDetails = configuration.shippingDetails {
            cfgbuilder = cfgbuilder.shippingDetails(shippingDetails.platformShippingDetails)
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
        #endif
        #endif
    }
}

/// A bridgeable payment button for SkipFuse that only handles a string button label.
public struct SimpleStripePaymentButton: View {
    let configuration: StripePaymentConfiguration
    let completion: (StripePaymentResult) -> Void
    let buttonText: String

    public init(configuration: StripePaymentConfiguration, buttonText: String, completion: @escaping (StripePaymentResult) -> Void) {
        self.configuration = configuration
        self.completion = completion
        self.buttonText = buttonText
    }

    public var body: some View {
        StripePaymentButton(configuration: configuration, completion: completion) {
            Text(buttonText)
        }
    }
}
#endif
