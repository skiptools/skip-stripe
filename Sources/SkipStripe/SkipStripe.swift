// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
//
// SkipStripe.swift
//
// A cross-platform Stripe SDK wrapper for Skip Fuse (iOS + Android).
// This module is transpiled (mode: 'transpiled', bridging: true in skip.yml)
// so Swift code is transpiled to Kotlin for Android and the public API is
// bridged back to native Swift via Skip Fuse.
//
// This file provides:
//
// 1. PAYMENT SHEET (online payments)
//    - StripePaymentConfiguration: Cross-platform payment sheet config
//    - StripePaymentButton / SimpleStripePaymentButton: SwiftUI views that
//      present the Stripe PaymentSheet on iOS (native) and Android (transpiled).
//    - Supporting types: CardBrand, Address, BillingDetails, AddressDetails,
//      ApplePayConfiguration, GooglePayConfiguration.
//
// 2. STRIPE TERMINAL (in-person payments with physical readers)
//    - StripeTerminalManager: Singleton that manages the full Terminal lifecycle:
//      • Initialization with a connection token provider
//      • Reader discovery (Bluetooth, Internet, Tap to Pay)
//      • Reader connection (Bluetooth, Internet, Tap to Pay)
//      • Payment collection (create → collect → confirm PaymentIntent)
//      • Reader disconnection
//      • Firmware update progress tracking
//    - StripeTerminalReader: Model representing a discovered/connected reader.
//    - StripeTerminalTokenProvider: Protocol your app implements to fetch
//      connection tokens from your backend.
//    - StripeTerminalDelegate: Optional delegate for Terminal event callbacks.
//    - URLConnectionTokenProvider: Built-in token provider that calls a
//      Firebase Cloud Function with Firebase Auth (Android only, via SKIP INSERT).
//    - AuthenticatedCloudFunctionCaller: Helper for calling any Cloud Function
//      with Firebase Auth bearer tokens (Android only, via SKIP INSERT).
//    - Enums: TerminalConnectionStatus, TerminalPaymentStatus, TerminalResult,
//      ReaderDeviceType, ReaderDiscoveryMethod.
//
// 3. iOS HELPER CLASSES (compiled only on iOS)
//    - ConnectionTokenProviderWrapper: Bridges StripeTerminalTokenProvider
//      to the native StripeTerminal SDK's ConnectionTokenProvider protocol.
//    - TerminalDelegateWrapper: Bridges StripeTerminal.TerminalDelegate to
//      StripeTerminalManager's state and delegate.
//    - ReaderDiscoveryDelegateWrapper: Bridges StripeTerminal.DiscoveryDelegate
//      to update StripeTerminalManager.discoveredReaders.
//    - ReaderConnectionDelegate: Implements TapToPayReaderDelegate,
//      MobileReaderDelegate, and InternetReaderDelegate for reader lifecycle
//      events (firmware updates, reconnection, disconnection).
//
// ARCHITECTURE NOTES:
// - Android code uses "SKIP INSERT" blocks to inject raw Kotlin that runs
//   directly on the Android Stripe Terminal SDK. This is necessary because
//   the Stripe Terminal Android SDK uses Kotlin callbacks/interfaces that
//   cannot be expressed in transpiled Swift.
// - iOS code uses the native StripeTerminal Swift SDK directly.
// - The #if SKIP / #elseif os(iOS) pattern ensures each platform gets its
//   own native implementation while exposing a unified Swift API.
//
#if !SKIP_BRIDGE
import Foundation
import SwiftUI

// ============================================================================
// MARK: - Platform Imports
// ============================================================================

#if SKIP
// Android: Stripe PaymentSheet SDK
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.PaymentSheetResultCallback
// Android: Stripe Terminal SDK
import com.stripe.stripeterminal.Terminal
import com.stripe.stripeterminal.external.callable.ConnectionTokenCallback
import com.stripe.stripeterminal.external.callable.ConnectionTokenProvider
import com.stripe.stripeterminal.external.callable.TerminalListener
import com.stripe.stripeterminal.external.callable.DiscoveryListener
import com.stripe.stripeterminal.external.callable.ReaderCallback
import com.stripe.stripeterminal.external.callable.PaymentIntentCallback
import com.stripe.stripeterminal.external.models.ConnectionStatus
import com.stripe.stripeterminal.external.models.PaymentStatus
import com.stripe.stripeterminal.external.models.Reader
import com.stripe.stripeterminal.external.models.DiscoveryConfiguration
import com.stripe.stripeterminal.external.models.ConnectionConfiguration
import com.stripe.stripeterminal.external.models.PaymentIntent
import com.stripe.stripeterminal.external.models.PaymentIntentParameters
import com.stripe.stripeterminal.external.models.TerminalException
import com.stripe.stripeterminal.log.LogLevel
#elseif os(iOS)
// iOS: Stripe PaymentSheet SDK
import Stripe
import StripeCore
import StripePayments
import StripePaymentsUI
import StripePaymentSheet
import PassKit
// iOS: Stripe Terminal SDK
import StripeTerminal
#endif

/// The configuration for a `StripePaymentButton`.
///
/// This vends an
/// iOS [`PaymentSheet.Configuration`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/configuration-swift.struct)
/// and
/// Android [`com.stripe.android.paymentsheet.PaymentSheet.Configuration`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-configuration/index.html)
public struct StripePaymentConfiguration {
    /// The customer-facing business name.
    public var merchantName: String

    /// The identifier of the Stripe Customer object.
    /// See https://stripe.com/docs/api/customers/object#customer_object-id
    public var customerID: String

    /// A short-lived token that allows the SDK to access a Customer's payment methods
    ///
    /// Represents an Ephemeral Key that can be used temporarily for API operations that typically require a secret key.
    /// See https://docs.stripe.com/mobile/android/basic#set-up-ephemeral-key
    public var ephemeralKeySecret: String

    public var clientSecret: String

    /// The label to use for the primary button.
    public var primaryButtonLabel: String?
    /// If true, allows payment methods that do not move money at the end of the checkout. Defaults to false.
    public var allowsDelayedPaymentMethods: Bool?
    /// If true, allows payment methods that require a shipping address, like Afterpay and Affirm. Defaults to false. Set this to true if you collect shipping addresses and set Configuration.shippingDetails or set shipping details directly on the PaymentIntent.
    public var allowsPaymentMethodsRequiringShippingAddress: Bool?
    /// The billing information for the customer.
    public var defaultBillingDetails: BillingDetails?
    /// The shipping information for the customer. If set, PaymentSheet will pre-populate the form fields with the values provided. This is used to display a "Billing address is same as shipping" checkbox if defaultBillingDetails is not provided. If name and line1 are populated, it's also attached to the PaymentIntent during payment.
    public var shippingDetails: AddressDetails?
    /// A list of preferred networks that should be used to process payments made with a co-branded card if your user hasn't selected a network themselves.
    public var preferredNetworks: [CardBrand]?
    /// Configuration related to Apple Pay. If set, PaymentSheet displays Apple Pay as a payment option (iOS only)
    public var applePay: ApplePayConfiguration?
    /// Configuration related to Google Pay. If set, PaymentSheet displays Google Pay as a payment option (Android only)
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
        typealias PlatformBillingDetails = PaymentSheet.BillingDetails // happens to be the same type name on iOS and Android
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
        typealias PlatformAddress = PaymentSheet.Address // happens to be the same type name on iOS and Android

        var platformAddress: PlatformAddress {
            PaymentSheet.Address(city: city, country: country, line1: line1, line2: line2, postalCode: postalCode, state: state)
        }
        #endif
    }

    /// Supporting for adding [Apple Pay](https://docs.stripe.com/payments/accept-a-payment?platform=ios&ui=payment-sheet&uikit-swiftui=swiftui#ios-apple-pay) as a payment option.
    ///
    /// Wraps the iOS [`PaymentSheet.ApplePayConfiguration`](https://stripe.dev/stripe-ios/stripepaymentsheet/documentation/stripepaymentsheet/paymentsheet/applepayconfiguration)
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
                /// A button with the Apple Pay logo only, useful when an additional call to action isn’t needed.
                case .plain: return PKPaymentButtonType.plain
                /// A button for product purchases.
                case .buy: return PKPaymentButtonType.buy
                /// A button for prompting the user to set up a card.
                case .setUp: return PKPaymentButtonType.setUp
                /// A button for paying bills or invoices.
                case .inStore: return PKPaymentButtonType.inStore
                /// A button used by approved nonprofit organization that lets people make donations.
                case .donate: return PKPaymentButtonType.donate
                /// A button for purchase experiences that include other payment buttons that start with “Check out”.
                case .checkout: return PKPaymentButtonType.checkout
                /// A button for booking trips, flights, or other experiences.
                case .book: return PKPaymentButtonType.book
                /// A button for purchasing a subscription.
                case .subscribe: return PKPaymentButtonType.subscribe
                /// A button for adding money to a card, account, or payment system.
                case .reload: return PKPaymentButtonType.reload
                /// A button for adding money to a card, account, or payment system.
                case .addMoney: return PKPaymentButtonType.addMoney
                /// A button for adding money to a card, account, or payment system.
                case .topUp: return PKPaymentButtonType.topUp
                /// A button for placing orders for such as like meals or flowers.
                case .order: return PKPaymentButtonType.order
                /// A button for renting items such as cars or scooters.
                case .rent: return PKPaymentButtonType.rent
                /// A button for supporting people give money to projects, causes, organizations, and other entities.
                case .support: return PKPaymentButtonType.support
                /// A button for to help people contribute money to projects, causes, organizations, and other entities.
                case .contribute: return PKPaymentButtonType.contribute
                /// A button for useful for letting people tip for goods or services.
                case .tip: return PKPaymentButtonType.tip
                /// A button for general purchases.
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

    /// Support for adding [Google Pay](https://docs.stripe.com/payments/accept-a-payment?platform=android&ui=payment-sheet#android-google-pay) as a option.
    ///
    /// Wraps [`com.stripe.android.paymentsheet.PaymentSheet.GooglePayConfiguration`](https://stripe.dev/stripe-android/paymentsheet/com.stripe.android.paymentsheet/-payment-sheet/-google-pay-configuration/index.html)
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
            if result is PaymentSheetResult.Completed {
                self.completion(StripePaymentResult.completed)
            } else if result is PaymentSheetResult.Canceled {
                self.completion(StripePaymentResult.canceled)
            } else if result is PaymentSheetResult.Failed {
                self.completion(StripePaymentResult.failed(error: ErrorException(result.error)))
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

// ============================================================================
// MARK: - Stripe Terminal Integration
// ============================================================================
//
// The Terminal section provides a cross-platform API for Stripe Terminal,
// enabling in-person payments with physical card readers on both iOS and Android.
//
// Lifecycle:
//   1. Initialize: Call StripeTerminalManager.shared.initialize(tokenProvider:)
//      with a StripeTerminalTokenProvider that fetches connection tokens from
//      your backend (e.g., a Firebase Cloud Function).
//   2. Discover: Call discoverReaders(method:simulated:) to scan for nearby
//      readers via Bluetooth, Internet, or Tap to Pay.
//   3. Connect: Call connectReader(_:locationId:completion:) with a discovered
//      reader. A Stripe Terminal Location ID is required for Bluetooth and
//      Tap to Pay readers.
//   4. Collect Payment: Call collectPayment(amount:currency:completion:) to
//      create a PaymentIntent, collect the card, and confirm the payment.
//   5. Disconnect: Call disconnectReader(completion:) when done.
//
// ============================================================================

/// Connection status for Terminal readers.
public enum TerminalConnectionStatus: Equatable {
    case notConnected
    case connecting
    case connected
}

/// Payment status for Terminal transactions.
public enum TerminalPaymentStatus: Equatable {
    case notReady
    case ready
    case waitingForInput
    case processing
}

/// Result of a Terminal operation.
public enum TerminalResult<T> {
    case success(T)
    case failure(error: Error)
}

/// Represents a discovered Terminal reader.
public struct StripeTerminalReader: Identifiable, Equatable {
    public let id: String
    public let serialNumber: String
    public let label: String?
    public let batteryLevel: Float?
    public let isCharging: Bool?
    public let deviceType: ReaderDeviceType
    
    public init(id: String, serialNumber: String, label: String? = nil, batteryLevel: Float? = nil, isCharging: Bool? = nil, deviceType: ReaderDeviceType = .unknown) {
        self.id = id
        self.serialNumber = serialNumber
        self.label = label
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.deviceType = deviceType
    }
    
    public static func == (lhs: StripeTerminalReader, rhs: StripeTerminalReader) -> Bool {
        lhs.id == rhs.id
    }
}

/// Reader device types supported by Terminal.
public enum ReaderDeviceType: Equatable {
    case chipper1X
    case chipper2X
    case stripeM2
    case wisePad3
    case wisePosE
    case stripeS700
    case stripeS700DevKit
    case appleBuiltIn // Tap to Pay on iPhone
    case tapToPay // Tap to Pay on Android
    case unknown
}

/// Discovery method for finding Terminal readers.
public enum ReaderDiscoveryMethod: Equatable {
    case bluetoothScan
    case internet
    case localMobile // Tap to Pay
}

/// Protocol for providing connection tokens to the Terminal SDK.
public protocol StripeTerminalTokenProvider {
    func fetchConnectionToken(completion: @escaping (String?, Error?) -> Void)
}

/// Delegate for Terminal events.
public protocol StripeTerminalDelegate: AnyObject {
    func terminalDidChangeConnectionStatus(_ status: TerminalConnectionStatus)
    func terminalDidChangePaymentStatus(_ status: TerminalPaymentStatus)
    func terminalDidDiscoverReaders(_ readers: [StripeTerminalReader])
    func terminalDidConnectReader(_ reader: StripeTerminalReader)
    func terminalDidDisconnectReader()
}

/// Extension to provide default implementations for optional delegate methods.
public extension StripeTerminalDelegate {
    func terminalDidChangeConnectionStatus(_ status: TerminalConnectionStatus) {}
    func terminalDidChangePaymentStatus(_ status: TerminalPaymentStatus) {}
    func terminalDidDiscoverReaders(_ readers: [StripeTerminalReader]) {}
    func terminalDidConnectReader(_ reader: StripeTerminalReader) {}
    func terminalDidDisconnectReader() {}
}

/// Built-in token provider that fetches connection tokens from a backend URL.
///
/// This class is designed for Android use via the transpiled Kotlin layer.
/// It calls your backend's `/createTerminalConnectionToken` endpoint with a
/// Firebase Auth bearer token. The backend should return JSON: `{ "secret": "pst_xxx" }`.
///
/// On iOS, you typically implement StripeTerminalTokenProvider directly in
/// your app using URLSession + FirebaseAuth (see the Terminal Guide for examples).
///
/// Usage (Android):
/// ```swift
/// let provider = URLConnectionTokenProvider(
///     backendURL: "https://us-central1-YOUR-PROJECT.cloudfunctions.net"
/// )
/// StripeTerminalManager.shared.initialize(tokenProvider: provider)
/// ```
public class URLConnectionTokenProvider: StripeTerminalTokenProvider {
    private let backendURL: String
    
    public init(backendURL: String) {
        self.backendURL = backendURL
    }
    
    public func fetchConnectionToken(completion: @escaping (String?, Error?) -> Void) {
        #if SKIP
        // SKIP INSERT:
        // val url = backendURL + "/createTerminalConnectionToken"
        // val user = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
        // if (user == null) {
        //     completion(null, skip.lib.ErrorException("User not authenticated"))
        //     return
        // }
        // user.getIdToken(false).addOnSuccessListener { tokenResult ->
        //     val idToken = tokenResult.token ?: ""
        //     val thread = Thread {
        //         try {
        //             val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        //             conn.requestMethod = "POST"
        //             conn.setRequestProperty("Authorization", "Bearer $idToken")
        //             conn.setRequestProperty("Content-Type", "application/json")
        //             conn.doOutput = true
        //             conn.outputStream.write("{}".toByteArray())
        //             val responseCode = conn.responseCode
        //             if (responseCode == 200) {
        //                 val body = conn.inputStream.bufferedReader().readText()
        //                 val json = org.json.JSONObject(body)
        //                 val secret = json.optString("secret", "")
        //                 if (secret.isNotEmpty()) {
        //                     android.os.Handler(android.os.Looper.getMainLooper()).post { completion(secret, null) }
        //                 } else {
        //                     android.os.Handler(android.os.Looper.getMainLooper()).post { completion(null, skip.lib.ErrorException("No secret in response")) }
        //                 }
        //             } else {
        //                 android.os.Handler(android.os.Looper.getMainLooper()).post { completion(null, skip.lib.ErrorException("HTTP error: $responseCode")) }
        //             }
        //             conn.disconnect()
        //         } catch (e: Exception) {
        //             android.os.Handler(android.os.Looper.getMainLooper()).post { completion(null, skip.lib.ErrorException(e.message ?: "Network error")) }
        //         }
        //     }
        //     thread.start()
        // }.addOnFailureListener { e ->
        //     completion(null, skip.lib.ErrorException(e.message ?: "Failed to get ID token"))
        // }
        #endif
    }
}

/// Helper for calling Firebase Cloud Functions with authentication from Android.
///
/// This class lives in the transpiled Kotlin layer and uses Firebase Auth to get
/// an ID token, then makes an authenticated HTTP POST request to a Cloud Function.
/// Native Swift code on Android can call this via Skip Fuse bridging.
///
/// This is used for operations like creating Terminal Locations or registering
/// readers, where you need to call your backend with authentication.
///
/// On iOS, use URLSession + FirebaseAuth directly instead.
public class AuthenticatedCloudFunctionCaller {
    public static let shared = AuthenticatedCloudFunctionCaller()
    private init() {}
    
    /// Call a Cloud Function endpoint with Firebase Auth bearer token.
    /// - Parameters:
    ///   - url: The full URL of the Cloud Function
    ///   - jsonBody: JSON string body to POST
    ///   - completion: Callback with (success, responseBody)
    public func call(url: String, jsonBody: String, completion: @escaping (Bool, String?) -> Void) {
        #if SKIP
        // SKIP INSERT:
        // val user = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
        // if (user == null) {
        //     completion(false, "User not authenticated")
        //     return
        // }
        // user.getIdToken(false).addOnSuccessListener { tokenResult ->
        //     val idToken = tokenResult.token ?: ""
        //     val thread = Thread {
        //         try {
        //             val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
        //             conn.requestMethod = "POST"
        //             conn.setRequestProperty("Authorization", "Bearer $idToken")
        //             conn.setRequestProperty("Content-Type", "application/json")
        //             conn.doOutput = true
        //             conn.outputStream.write(jsonBody.toByteArray())
        //             conn.outputStream.close()
        //             val responseCode = conn.responseCode
        //             val stream = if (responseCode in 200..299) conn.inputStream else conn.errorStream
        //             val body = stream.bufferedReader().readText()
        //             stream.close()
        //             conn.disconnect()
        //             val success = responseCode in 200..299
        //             android.os.Handler(android.os.Looper.getMainLooper()).post {
        //                 completion(success, body)
        //             }
        //         } catch (e: Exception) {
        //             android.os.Handler(android.os.Looper.getMainLooper()).post {
        //                 completion(false, e.message ?: "Network error")
        //             }
        //         }
        //     }
        //     thread.start()
        // }.addOnFailureListener { e ->
        //     completion(false, e.message ?: "Failed to get ID token")
        // }
        #else
        // iOS: use URLSession + FirebaseAuth (not used here, iOS has its own service)
        completion(false, "Not implemented on iOS")
        #endif
    }
}

/// Main Terminal manager class for handling reader connections and payments.
///
/// This singleton manages the complete Stripe Terminal lifecycle on both iOS and Android:
///
/// **State Properties (Observable):**
/// - `connectionStatus`: Current reader connection state (.notConnected, .connecting, .connected)
/// - `paymentStatus`: Current payment state (.notReady, .ready, .waitingForInput, .processing)
/// - `discoveredReaders`: Array of readers found during discovery
/// - `connectedReader`: The currently connected reader (nil if none)
/// - `isUpdatingFirmware`: Whether a firmware update is in progress
/// - `firmwareUpdateProgress`: Firmware update progress (0.0 to 1.0)
///
/// **Key Methods:**
/// - `initialize(tokenProvider:)` — Initialize the Terminal SDK (call once at app launch)
/// - `discoverReaders(method:simulated:)` — Scan for readers via Bluetooth/Internet/Tap to Pay
/// - `cancelDiscovery()` — Stop an ongoing reader scan
/// - `connectReader(_:locationId:completion:)` — Connect to a discovered reader
/// - `disconnectReader(completion:)` — Disconnect from the current reader
/// - `collectPayment(amount:currency:completion:)` — Full payment flow: create → collect → confirm
/// - `cancelPayment()` — Cancel an in-progress payment collection
///
/// **Platform Implementation:**
/// - iOS: Uses the native StripeTerminal Swift SDK with delegate wrappers
/// - Android: Uses SKIP INSERT blocks to call the Stripe Terminal Android SDK in Kotlin
@Observable public class StripeTerminalManager {
    public static let shared = StripeTerminalManager()
    
    public fileprivate(set) var connectionStatus: TerminalConnectionStatus = .notConnected
    public fileprivate(set) var paymentStatus: TerminalPaymentStatus = .notReady
    public fileprivate(set) var discoveredReaders: [StripeTerminalReader] = []
    public fileprivate(set) var connectedReader: StripeTerminalReader?
    public fileprivate(set) var isUpdatingFirmware: Bool = false
    public fileprivate(set) var firmwareUpdateProgress: Double = 0.0
    
    public weak var delegate: StripeTerminalDelegate?
    
    private var tokenProvider: StripeTerminalTokenProvider?
    private var isInitialized = false
    
    #if os(iOS)
    private var discoveryCancelable: Cancelable?
    private var paymentCancelable: Cancelable?
    private var discoveryDelegate: ReaderDiscoveryDelegateWrapper?
    #else
    private var discoveryCancelable: Any?
    private var paymentCancelable: Any?
    // SKIP INSERT: private var _lastDiscoveredAndroidReaders: MutableList<Reader> = mutableListOf()
    #endif
    
    private init() {}
    
    /// Initialize the Terminal SDK with a connection token provider.
    ///
    /// Must be called once before any other Terminal operations. Safe to call multiple times
    /// (subsequent calls are no-ops).
    ///
    /// - Parameter tokenProvider: An object conforming to `StripeTerminalTokenProvider` that
    ///   fetches connection tokens from your backend server. The Terminal SDK calls this
    ///   automatically whenever it needs a new token.
    ///
    /// **iOS:** Calls `Terminal.initWithTokenProvider()` with a bridged wrapper.
    /// **Android:** Uses SKIP INSERT to call `Terminal.init()` with a Kotlin ConnectionTokenProvider
    /// and TerminalListener that maps connection/payment status changes back to Swift enums.
    public func initialize(tokenProvider: StripeTerminalTokenProvider) {
        guard !isInitialized else { return }
        self.tokenProvider = tokenProvider
        
        #if os(iOS)
        let tokenProviderWrapper = ConnectionTokenProviderWrapper(provider: tokenProvider)
        Terminal.initWithTokenProvider(tokenProviderWrapper)
        #elseif SKIP
        // SKIP INSERT:
        // val mgr = this@StripeTerminalManager
        // val provider = mgr.tokenProvider!!
        // val terminalTokenProvider = object : ConnectionTokenProvider {
        //     override fun fetchConnectionToken(callback: ConnectionTokenCallback) {
        //         provider.fetchConnectionToken { token, error ->
        //             if (token != null) {
        //                 callback.onSuccess(token)
        //             } else {
        //                 callback.onFailure(
        //                     com.stripe.stripeterminal.external.models.ConnectionTokenException("Failed to fetch connection token: ${error?.localizedDescription ?: "unknown"}")
        //                 )
        //             }
        //         }
        //     }
        // }
        // if (!Terminal.isInitialized()) {
        //     Terminal.init(ProcessInfo.processInfo.androidContext, LogLevel.VERBOSE, terminalTokenProvider, object : TerminalListener {
        //         override fun onConnectionStatusChange(status: ConnectionStatus) {
        //             mgr.connectionStatus = when (status) {
        //                 ConnectionStatus.NOT_CONNECTED -> TerminalConnectionStatus.notConnected
        //                 ConnectionStatus.CONNECTING -> TerminalConnectionStatus.connecting
        //                 ConnectionStatus.CONNECTED -> TerminalConnectionStatus.connected
        //                 else -> TerminalConnectionStatus.notConnected
        //             }
        //         }
        //         override fun onPaymentStatusChange(status: PaymentStatus) {
        //             mgr.paymentStatus = when (status) {
        //                 PaymentStatus.NOT_READY -> TerminalPaymentStatus.notReady
        //                 PaymentStatus.READY -> TerminalPaymentStatus.ready
        //                 PaymentStatus.WAITING_FOR_INPUT -> TerminalPaymentStatus.waitingForInput
        //                 PaymentStatus.PROCESSING -> TerminalPaymentStatus.processing
        //                 else -> TerminalPaymentStatus.notReady
        //             }
        //         }
        //     }, null)
        // }
        #endif
        
        isInitialized = true
    }
    
    /// Discover available Terminal readers.
    ///
    /// Starts scanning for readers using the specified discovery method. Results are
    /// accumulated in `discoveredReaders` and reported via the delegate.
    ///
    /// - Parameters:
    ///   - method: `.bluetoothScan` for portable readers (M2, Chipper),
    ///     `.internet` for countertop readers (S700, WisePOS E),
    ///     `.localMobile` for Tap to Pay on iPhone/Android.
    ///   - simulated: Set to `true` to discover simulated readers for testing.
    ///
    /// **iOS:** Uses DiscoveryConfiguration builders and a DiscoveryDelegate wrapper.
    /// The discovery delegate is stored as a strong reference to prevent ARC deallocation.
    /// **Android:** Uses SKIP INSERT to create the appropriate DiscoveryConfiguration and
    /// DiscoveryListener, mapping discovered Android Reader objects to StripeTerminalReader.
    public func discoverReaders(method: ReaderDiscoveryMethod, simulated: Bool = false) {
        guard isInitialized else { return }
        discoveredReaders = []
        
        #if os(iOS)
        let discoveryConfig: DiscoveryConfiguration
        switch method {
        case .bluetoothScan:
            discoveryConfig = try! BluetoothScanDiscoveryConfigurationBuilder().setSimulated(simulated).build()
        case .internet:
            discoveryConfig = try! InternetDiscoveryConfigurationBuilder().setSimulated(simulated).build()
        case .localMobile:
            discoveryConfig = try! TapToPayDiscoveryConfigurationBuilder().setSimulated(simulated).build()
        }
        
        discoveryDelegate = ReaderDiscoveryDelegateWrapper(manager: self)
        discoveryCancelable = Terminal.shared.discoverReaders(discoveryConfig, delegate: discoveryDelegate!) { error in
            if let error = error {
                print("Discovery error: \(error)")
            }
        }
        #elseif SKIP
        // SKIP INSERT:
        // val mgr = this@StripeTerminalManager
        // val config = when (method) {
        //     ReaderDiscoveryMethod.bluetoothScan -> com.stripe.stripeterminal.external.models.DiscoveryConfiguration.BluetoothDiscoveryConfiguration(timeout = 0, isSimulated = simulated)
        //     ReaderDiscoveryMethod.internet -> com.stripe.stripeterminal.external.models.DiscoveryConfiguration.InternetDiscoveryConfiguration(isSimulated = simulated)
        //     ReaderDiscoveryMethod.localMobile -> com.stripe.stripeterminal.external.models.DiscoveryConfiguration.TapToPayDiscoveryConfiguration(isSimulated = simulated)
        //     else -> com.stripe.stripeterminal.external.models.DiscoveryConfiguration.BluetoothDiscoveryConfiguration(timeout = 0, isSimulated = simulated)
        // }
        // mgr.discoveryCancelable = Terminal.getInstance().discoverReaders(config, object : DiscoveryListener {
        //     override fun onUpdateDiscoveredReaders(readers: List<Reader>) {
        //         mgr._lastDiscoveredAndroidReaders.clear()
        //         mgr._lastDiscoveredAndroidReaders.addAll(readers)
        //         val mapped = skip.lib.Array<StripeTerminalReader>()
        //         for (reader in readers) {
        //             mapped.append(StripeTerminalReader(
        //                 id = reader.serialNumber ?: "",
        //                 serialNumber = reader.serialNumber ?: "",
        //                 label = reader.label,
        //                 batteryLevel = reader.batteryLevel,
        //                 isCharging = null,
        //                 deviceType = ReaderDeviceType.unknown
        //             ))
        //         }
        //         mgr.discoveredReaders = mapped
        //         mgr.delegate?.terminalDidDiscoverReaders(mgr.discoveredReaders)
        //     }
        // }, object : com.stripe.stripeterminal.external.callable.Callback {
        //     override fun onSuccess() { }
        //     override fun onFailure(e: TerminalException) {
        //         println("Discovery error: ${e.errorMessage}")
        //     }
        // })
        #endif
    }
    
    /// Cancel ongoing reader discovery.
    public func cancelDiscovery() {
        #if os(iOS)
        discoveryCancelable?.cancel { _ in }
        #elseif SKIP
        // SKIP INSERT:
        // (this@StripeTerminalManager.discoveryCancelable as? com.stripe.stripeterminal.external.callable.Cancelable)?.cancel(object : com.stripe.stripeterminal.external.callable.Callback {
        //     override fun onSuccess() { }
        //     override fun onFailure(e: TerminalException) { }
        // })
        #endif
        discoveryCancelable = nil
    }
    
    /// Connect to a discovered reader.
    ///
    /// Establishes a connection to the specified reader. The connection type is
    /// automatically determined by the reader's device type:
    /// - **Bluetooth readers** (M2, Chipper 2X, WisePad 3): Requires a `locationId`.
    /// - **Tap to Pay** (Apple Built-In / Android NFC): Requires a `locationId`.
    /// - **Internet readers** (S700, WisePOS E): locationId optional.
    ///
    /// A Terminal Location must be created in your Stripe account before connecting
    /// Bluetooth or Tap to Pay readers. Use the `createTerminalLocationV1` Cloud
    /// Function or the Stripe Dashboard to create one.
    ///
    /// - Parameters:
    ///   - reader: A `StripeTerminalReader` from the `discoveredReaders` array.
    ///   - locationId: The Stripe Terminal Location ID (e.g., `tml_xxx`). Required
    ///     for Bluetooth and Tap to Pay readers.
    ///   - completion: Called with `.success(connectedReader)` or `.failure(error)`.
    ///
    /// **iOS:** Builds the appropriate ConnectionConfiguration based on device type,
    /// creates a ReaderConnectionDelegate for firmware/reconnection events, and calls
    /// `Terminal.shared.connectReader()`.
    /// **Android:** Uses SKIP INSERT to determine if the reader is Internet or Bluetooth,
    /// creates the matching ConnectionConfiguration with a MobileReaderListener for
    /// firmware updates, and calls `Terminal.getInstance().connectReader()`.
    public func connectReader(_ reader: StripeTerminalReader, locationId: String? = nil, completion: @escaping (TerminalResult<StripeTerminalReader>) -> Void) {
        guard isInitialized else {
            completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Terminal not initialized"])))
            return
        }
        
        connectionStatus = .connecting
        
        #if os(iOS)
        guard let platformReader = findPlatformReader(reader) else {
            completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reader not found"])))
            return
        }
        
        let connectionConfig: ConnectionConfiguration
        let readerDelegate = ReaderConnectionDelegate(manager: self)
        switch reader.deviceType {
        case .appleBuiltIn:
            guard let locId = locationId, !locId.isEmpty else {
                connectionStatus = .notConnected
                completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "A location ID is required to connect to a Tap to Pay reader. Please set up a Terminal location first."])))
                return
            }
            connectionConfig = try! TapToPayConnectionConfigurationBuilder(delegate: readerDelegate, locationId: locId).build()
        case .stripeM2, .chipper2X, .wisePad3:
            guard let locId = locationId, !locId.isEmpty else {
                connectionStatus = .notConnected
                completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "A location ID is required to connect to a Bluetooth reader. Please set up a Terminal location first."])))
                return
            }
            connectionConfig = try! BluetoothConnectionConfigurationBuilder(delegate: readerDelegate, locationId: locId).build()
        default:
            connectionConfig = try! InternetConnectionConfigurationBuilder(delegate: readerDelegate).build()
        }
        
        Terminal.shared.connectReader(platformReader, connectionConfig: connectionConfig) { connectedReader, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.connectionStatus = .notConnected
                    completion(.failure(error: error))
                } else if let connectedReader = connectedReader {
                    let mappedReader = self.mapReader(connectedReader)
                    self.connectedReader = mappedReader
                    self.connectionStatus = .connected
                    self.delegate?.terminalDidConnectReader(mappedReader)
                    completion(.success(mappedReader))
                }
            }
        }
        #elseif SKIP
        // SKIP INSERT:
        // val mgr = this@StripeTerminalManager
        // val platformReader = mgr._lastDiscoveredAndroidReaders.firstOrNull { it.serialNumber == reader.serialNumber }
        // if (platformReader == null) {
        //     mgr.connectionStatus = TerminalConnectionStatus.notConnected
        //     completion(TerminalResult.failure(error = skip.lib.ErrorException("Reader not found")))
        //     return
        // }
        // val isInternetReader = platformReader.networkStatus != null
        // val connectionConfig: ConnectionConfiguration
        // if (isInternetReader) {
        //     connectionConfig = com.stripe.stripeterminal.external.models.ConnectionConfiguration.InternetConnectionConfiguration(internetReaderListener = object : com.stripe.stripeterminal.external.callable.InternetReaderListener { })
        // } else {
        //     val readerListener = object : com.stripe.stripeterminal.external.callable.MobileReaderListener {
        //         override fun onStartInstallingUpdate(update: com.stripe.stripeterminal.external.models.ReaderSoftwareUpdate, cancelable: com.stripe.stripeterminal.external.callable.Cancelable?) {
        //             mgr.isUpdatingFirmware = true
        //             mgr.firmwareUpdateProgress = 0.0
        //         }
        //         override fun onReportReaderSoftwareUpdateProgress(progress: Float) {
        //             mgr.firmwareUpdateProgress = progress.toDouble()
        //         }
        //         override fun onFinishInstallingUpdate(update: com.stripe.stripeterminal.external.models.ReaderSoftwareUpdate?, e: TerminalException?) {
        //             mgr.isUpdatingFirmware = false
        //             mgr.firmwareUpdateProgress = 1.0
        //         }
        //         override fun onRequestReaderInput(options: com.stripe.stripeterminal.external.models.ReaderInputOptions) { }
        //         override fun onRequestReaderDisplayMessage(message: com.stripe.stripeterminal.external.models.ReaderDisplayMessage) { }
        //     }
        //     connectionConfig = com.stripe.stripeterminal.external.models.ConnectionConfiguration.BluetoothConnectionConfiguration(locationId ?: "", autoReconnectOnUnexpectedDisconnect = false, bluetoothReaderListener = readerListener)
        // }
        // Terminal.getInstance().connectReader(platformReader, connectionConfig, object : ReaderCallback {
        //     override fun onSuccess(connReader: Reader) {
        //         val mapped = StripeTerminalReader(id = connReader.serialNumber ?: "", serialNumber = connReader.serialNumber ?: "", label = connReader.label, batteryLevel = connReader.batteryLevel, isCharging = null, deviceType = ReaderDeviceType.unknown)
        //         mgr.connectedReader = mapped
        //         mgr.connectionStatus = TerminalConnectionStatus.connected
        //         mgr.delegate?.terminalDidConnectReader(mapped)
        //         completion(TerminalResult.success(mapped))
        //     }
        //     override fun onFailure(e: TerminalException) {
        //         mgr.connectionStatus = TerminalConnectionStatus.notConnected
        //         completion(TerminalResult.failure(error = skip.lib.ErrorException(e.errorMessage ?: "Connection failed")))
        //     }
        // })
        #endif
    }
    
    /// Disconnect from the current reader.
    public func disconnectReader(completion: @escaping (Error?) -> Void) {
        #if os(iOS)
        Terminal.shared.disconnectReader { error in
            DispatchQueue.main.async {
                if error == nil {
                    self.connectedReader = nil
                    self.connectionStatus = .notConnected
                    self.delegate?.terminalDidDisconnectReader()
                }
                completion(error)
            }
        }
        #elseif SKIP
        // SKIP INSERT:
        // val mgr = this@StripeTerminalManager
        // Terminal.getInstance().disconnectReader(object : com.stripe.stripeterminal.external.callable.Callback {
        //     override fun onSuccess() {
        //         mgr.connectedReader = null
        //         mgr.connectionStatus = TerminalConnectionStatus.notConnected
        //         mgr.delegate?.terminalDidDisconnectReader()
        //         completion(null)
        //     }
        //     override fun onFailure(e: TerminalException) {
        //         completion(skip.lib.ErrorException(e.errorMessage ?: "Disconnect failed"))
        //     }
        // })
        #endif
    }
    
    /// Collect a payment using the connected reader.
    ///
    /// Performs the full payment flow in three steps:
    /// 1. **Create** a PaymentIntent with the specified amount and currency.
    /// 2. **Collect** the payment method by prompting the customer to present
    ///    their card (tap, insert, or swipe depending on reader type).
    /// 3. **Confirm** the PaymentIntent to finalize the charge.
    ///
    /// On success, returns the PaymentIntent ID (e.g., `pi_xxx`) which you can
    /// use to track the payment in your backend.
    ///
    /// - Parameters:
    ///   - amount: The charge amount in the smallest currency unit (e.g., cents for USD).
    ///   - currency: ISO currency code (e.g., `"usd"`).
    ///   - completion: Called with `.success(paymentIntentId)` or `.failure(error)`.
    ///
    /// **iOS:** Chains `createPaymentIntent` → `collectPaymentMethod` → `confirmPaymentIntent`
    /// using the native StripeTerminal SDK callbacks.
    /// **Android:** Uses SKIP INSERT to chain the same three steps via Kotlin PaymentIntentCallback.
    public func collectPayment(amount: Int, currency: String, completion: @escaping (TerminalResult<String>) -> Void) {
        guard isInitialized, connectedReader != nil else {
            completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "No reader connected"])))
            return
        }
        
        #if os(iOS)
        let params = try! PaymentIntentParametersBuilder(amount: UInt(amount), currency: currency).build()
        
        Terminal.shared.createPaymentIntent(params) { paymentIntent, createError in
            if let error = createError {
                completion(.failure(error: error))
                return
            }
            
            guard let paymentIntent = paymentIntent else {
                completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PaymentIntent"])))
                return
            }
            
            self.paymentCancelable = Terminal.shared.collectPaymentMethod(paymentIntent) { collectResult, collectError in
                if let error = collectError {
                    completion(.failure(error: error))
                    return
                }
                
                guard let collectedIntent = collectResult else {
                    completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to collect payment method"])))
                    return
                }
                
                Terminal.shared.confirmPaymentIntent(collectedIntent) { confirmedIntent, confirmError in
                    DispatchQueue.main.async {
                        if let error = confirmError {
                            completion(.failure(error: error))
                        } else if let confirmedIntent = confirmedIntent, let stripeId = confirmedIntent.stripeId {
                            completion(.success(stripeId))
                        } else {
                            completion(.failure(error: NSError(domain: "StripeTerminal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to confirm payment"])))
                        }
                    }
                }
            }
        }
        #elseif SKIP
        // SKIP INSERT:
        // val params = PaymentIntentParameters.Builder().setAmount(amount.toLong()).setCurrency(currency).build()
        // Terminal.getInstance().createPaymentIntent(params, object : PaymentIntentCallback {
        //     override fun onSuccess(paymentIntent: PaymentIntent) {
        //         Terminal.getInstance().collectPaymentMethod(paymentIntent, object : PaymentIntentCallback {
        //             override fun onSuccess(collectedIntent: PaymentIntent) {
        //                 Terminal.getInstance().confirmPaymentIntent(collectedIntent, object : PaymentIntentCallback {
        //                     override fun onSuccess(confirmedIntent: PaymentIntent) {
        //                         val piId = confirmedIntent.id ?: ""
        //                         completion(TerminalResult.success(piId))
        //                     }
        //                     override fun onFailure(e: TerminalException) {
        //                         completion(TerminalResult.failure(error = skip.lib.ErrorException(e.errorMessage ?: "Confirm failed")))
        //                     }
        //                 })
        //             }
        //             override fun onFailure(e: TerminalException) {
        //                 completion(TerminalResult.failure(error = skip.lib.ErrorException(e.errorMessage ?: "Collect failed")))
        //             }
        //         })
        //     }
        //     override fun onFailure(e: TerminalException) {
        //         completion(TerminalResult.failure(error = skip.lib.ErrorException(e.errorMessage ?: "Create PI failed")))
        //     }
        // })
        #endif
    }
    
    /// Cancel the current payment collection.
    public func cancelPayment() {
        #if os(iOS)
        paymentCancelable?.cancel { _ in }
        #elseif SKIP
        // SKIP INSERT:
        // (this@StripeTerminalManager.paymentCancelable as? com.stripe.stripeterminal.external.callable.Cancelable)?.cancel(object : com.stripe.stripeterminal.external.callable.Callback {
        //     override fun onSuccess() { }
        //     override fun onFailure(e: TerminalException) { }
        // })
        #endif
        paymentCancelable = nil
    }
    
    // MARK: - Private Helpers
    
    #if os(iOS)
    private var lastDiscoveredReaders: [Reader] = []
    
    private func findPlatformReader(_ reader: StripeTerminalReader) -> Reader? {
        return lastDiscoveredReaders.first { $0.serialNumber == reader.serialNumber }
    }
    
    fileprivate func updateDiscoveredReaders(_ readers: [Reader]) {
        lastDiscoveredReaders = readers
        discoveredReaders = readers.map { mapReader($0) }
        delegate?.terminalDidDiscoverReaders(discoveredReaders)
    }
    
    private func mapReader(_ reader: Reader) -> StripeTerminalReader {
        // Check if this is a Tap to Pay reader (simulated local reader or built-in NFC)
        let deviceType: ReaderDeviceType
        if reader.simulated && reader.deviceType == .stripeM2 {
            // Simulated Tap to Pay readers may appear as stripeM2
            deviceType = mapDeviceType(reader.deviceType)
        } else {
            deviceType = mapDeviceType(reader.deviceType)
        }
        
        return StripeTerminalReader(
            id: reader.serialNumber,
            serialNumber: reader.serialNumber,
            label: reader.label,
            batteryLevel: reader.batteryLevel?.floatValue,
            isCharging: reader.isCharging?.boolValue,
            deviceType: deviceType
        )
    }
    
    private func mapDeviceType(_ type: DeviceType) -> ReaderDeviceType {
        switch type {
        case .chipper2X: return .chipper2X
        case .stripeM2: return .stripeM2
        case .wisePad3: return .wisePad3
        case .wisePosE: return .wisePosE
        case .stripeS700: return .stripeS700
        @unknown default: return .appleBuiltIn // Tap to Pay readers use unknown device type
        }
    }
    
    fileprivate func mapConnectionStatus(_ status: StripeTerminal.ConnectionStatus) -> TerminalConnectionStatus {
        switch status {
        case .notConnected: return .notConnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .reconnecting: return .connecting // Map reconnecting to connecting
        @unknown default: return .notConnected
        }
    }
    
    fileprivate func mapPaymentStatus(_ status: StripeTerminal.PaymentStatus) -> TerminalPaymentStatus {
        switch status {
        case .notReady: return .notReady
        case .ready: return .ready
        case .waitingForInput: return .waitingForInput
        case .processing: return .processing
        @unknown default: return .notReady
        }
    }
    #endif
}

// ============================================================================
// MARK: - iOS Helper Classes
// ============================================================================
//
// These classes bridge SkipStripe's cross-platform protocols to the native
// StripeTerminal iOS SDK delegate protocols. They are compiled only on iOS.
//
// - ConnectionTokenProviderWrapper: Bridges StripeTerminalTokenProvider → ConnectionTokenProvider
// - TerminalDelegateWrapper: Bridges Terminal delegate → StripeTerminalManager state updates
// - ReaderDiscoveryDelegateWrapper: Bridges DiscoveryDelegate → StripeTerminalManager.discoveredReaders
//   NOTE: Stored as a strong reference on StripeTerminalManager to prevent ARC deallocation.
//   The Stripe SDK holds only a weak reference to the delegate.
// - ReaderConnectionDelegate: Handles reader lifecycle events (firmware updates, reconnection,
//   disconnection) for all reader types (Tap to Pay, Bluetooth, Internet).
//
// ============================================================================

#if os(iOS)
/// Bridges StripeTerminalTokenProvider to the native iOS ConnectionTokenProvider protocol.
private class ConnectionTokenProviderWrapper: ConnectionTokenProvider {
    let provider: StripeTerminalTokenProvider
    
    init(provider: StripeTerminalTokenProvider) {
        self.provider = provider
    }
    
    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        provider.fetchConnectionToken { secret, error in
            completion(secret, error)
        }
    }
}

private class TerminalDelegateWrapper: NSObject, TerminalDelegate {
    weak var manager: StripeTerminalManager?
    
    init(manager: StripeTerminalManager) {
        self.manager = manager
    }
    
    func terminal(_ terminal: Terminal, didChangeConnectionStatus status: StripeTerminal.ConnectionStatus) {
        DispatchQueue.main.async {
            self.manager?.connectionStatus = self.manager?.mapConnectionStatus(status) ?? .notConnected
            if let status = self.manager?.connectionStatus {
                self.manager?.delegate?.terminalDidChangeConnectionStatus(status)
            }
        }
    }
    
    func terminal(_ terminal: Terminal, didChangePaymentStatus status: StripeTerminal.PaymentStatus) {
        DispatchQueue.main.async {
            self.manager?.paymentStatus = self.manager?.mapPaymentStatus(status) ?? .notReady
            if let status = self.manager?.paymentStatus {
                self.manager?.delegate?.terminalDidChangePaymentStatus(status)
            }
        }
    }
}

private class ReaderDiscoveryDelegateWrapper: NSObject, DiscoveryDelegate {
    weak var manager: StripeTerminalManager?
    
    init(manager: StripeTerminalManager) {
        self.manager = manager
    }
    
    func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        DispatchQueue.main.async {
            self.manager?.updateDiscoveredReaders(readers)
        }
    }
}

private class ReaderConnectionDelegate: NSObject, TapToPayReaderDelegate, MobileReaderDelegate, InternetReaderDelegate {
    func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
    }
    
    func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
    }
    
    func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: (any Error)?) {
    }
    
    func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions = []) {
    }
    
    func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
    }
    
    func reader(_ reader: Reader, didReportAvailableUpdate update: ReaderSoftwareUpdate) {
    }
    
    func reader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
    }
    
    func reader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: (any Error)?) {
    }
    
    weak var manager: StripeTerminalManager?
    
    init(manager: StripeTerminalManager) {
        self.manager = manager
        super.init()
    }
    
    // MARK: - Common reconnection methods (TapToPayReaderDelegate & MobileReaderDelegate)
    func reader(_ reader: Reader, didStartReconnect cancelable: Cancelable) {
        DispatchQueue.main.async {
            self.manager?.connectionStatus = .connecting
        }
    }
    
    func readerDidSucceedReconnect(_ reader: Reader) {
        DispatchQueue.main.async {
            self.manager?.connectionStatus = .connected
        }
    }
    
    func readerDidFailReconnect(_ reader: Reader) {
        DispatchQueue.main.async {
            self.manager?.connectedReader = nil
            self.manager?.connectionStatus = .notConnected
            self.manager?.delegate?.terminalDidDisconnectReader()
        }
    }
    
    // MARK: - MobileReaderDelegate specific methods
    func reader(_ reader: Reader, didReportReaderEvent event: ReaderEvent, info: [AnyHashable: Any]?) {}
    func reader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {}
    func reader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
    func reader(_ reader: Reader, didReportBatteryLevel batteryLevel: Float, status: BatteryStatus, isCharging: Bool) {}
    func reader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}
    
    // MARK: - InternetReaderDelegate
    func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {
        DispatchQueue.main.async {
            self.manager?.connectedReader = nil
            self.manager?.connectionStatus = .notConnected
            self.manager?.delegate?.terminalDidDisconnectReader()
        }
    }
}

#endif
#endif

