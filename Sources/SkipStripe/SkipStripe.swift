// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import SwiftUI

#if SKIP
// https://docs.stripe.com/payments/accept-a-payment?platform=android&ui=payment-sheet
import com.stripe.android.PaymentConfiguration
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
#elseif os(iOS)
// https://docs.stripe.com/payments/accept-a-payment?platform=ios&ui=payment-sheet&uikit-swiftui=swiftui
import Stripe
import StripeCore
import StripePayments
import StripePaymentsUI
import StripePaymentSheet
#endif

public class SkipStripeModule {
    public func stripeAPIDemo(merchantName: String) {
        #if SKIP
        let _ = PaymentSheet.Configuration.Builder(merchantDisplayName: merchantName)
        #elseif os(iOS)
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = merchantName
        #else
        fatalError("Unsupported platform")
        #endif
    }
}

public struct StripeView : View {
    public var body: some View {
        Text("Stripe integration WIP")
    }
}

