import SwiftUI
#if os(Android)
import SkipStripe
#else
import Stripe
#endif

struct ContentView: View {
    @State var authViewModel = AuthViewModel()
    @State var paymentErrorMessage: String?
    @State var stripeCustomerId: String?
    @State var paymentMethods: [StripePaymentService.StripePaymentMethod] = []
    @State var isLoadingPayment = false
    @State var isRefreshingPaymentMethods = false
#if os(Android)
    @State var androidPaymentConfiguration: StripePaymentConfiguration?
#endif

    var body: some View {
        @Bindable var authViewModel = authViewModel
        return NavigationStack {
            Group {
                if authViewModel.userEmail != nil {
                    authenticatedView
                } else {
                    loginView
                }
            }
            .navigationTitle(authViewModel.userEmail != nil ? "Payments" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if authViewModel.userEmail != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") {
                            authViewModel.signOut()
                        }
                    }
                }
            }
        }
        .onAppear {
            if authViewModel.userEmail != nil {
                Task { await prepareForPayments() }
            }
        }
        .onChange(of: authViewModel.userEmail) { _, newValue in
            if newValue != nil {
                Task { await prepareForPayments() }
            } else {
                stripeCustomerId = nil
                paymentMethods = []
                paymentErrorMessage = nil
#if os(Android)
                androidPaymentConfiguration = nil
#endif
            }
        }
    }

    private var loginView: some View {
        @Bindable var authViewModel = authViewModel
        return Form {
            Section("Account") {
                TextField("Email", text: $authViewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                SecureField("Password", text: $authViewModel.password)
            }

            if let error = authViewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await authViewModel.signIn() }
                } label: {
                    HStack {
                        Spacer()
                        if authViewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("Sign In")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(authViewModel.isLoading)
            }
        }
    }

    private var authenticatedView: some View {
        @Bindable var authViewModel = authViewModel
        return ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome")
                        .font(.largeTitle)
                    if let email = authViewModel.userEmail {
                        Text(email)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let message = paymentErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

#if os(Android)
                androidPaymentButton
#else
                Button {
                    Task { await handleAcceptPayment() }
                } label: {
                    acceptPaymentButtonLabel(isProcessing: isLoadingPayment)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingPayment)
#endif

                savedCardsSection
            }
            .padding()
        }
        .task {
            await prepareForPayments()
        }
    }

    private var savedCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved cards")
                .font(.headline)

            if isRefreshingPaymentMethods {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Refreshing…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if paymentMethods.isEmpty {
                Text("No saved cards yet. Cards used during checkout will be saved for future use.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paymentMethods) { method in
                    savedCardRow(for: method)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func acceptPaymentButtonLabel(isProcessing: Bool) -> some View {
        HStack {
            Spacer()
            if isProcessing {
                ProgressView()
            } else {
                Text("Accept Payment")
                    .font(.title2)
                    .padding(.vertical, 12)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func savedCardRow(for method: StripePaymentService.StripePaymentMethod) -> some View {
        if let card = method.card {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(card.brand ?? "Card") ••••\(card.last4 ?? "????")")
                    .font(.body)
                if let expMonth = card.expMonth, let expYear = card.expYear {
                    Text("Expires \(expMonth)/\(expYear)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Card saved for future use.")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
        } else {
            Text(method.id)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                )
        }
    }

    @MainActor
    private func prepareForPayments() async {
        guard stripeCustomerId == nil else {
            await refreshPaymentMethods()
            return
        }

        do {
            let customer = try await StripePaymentService.shared.ensureCustomer()
            stripeCustomerId = customer.stripeCustomerId
            await refreshPaymentMethods()
        } catch {
            paymentErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshPaymentMethods() async {
        guard let stripeCustomerId else { return }
        isRefreshingPaymentMethods = true
        defer { isRefreshingPaymentMethods = false }

        do {
            let methods = try await StripePaymentService.shared.listPaymentMethods(stripeCustomerId: stripeCustomerId)
            paymentMethods = methods
            paymentErrorMessage = nil
#if os(Android)
            await ensureAndroidPaymentConfiguration()
#endif
        } catch {
            paymentErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleAcceptPayment() async {
#if os(Android)
        await prepareAndroidPaymentConfiguration(triggeredByUser: true)
#else
        guard !isLoadingPayment else { return }
        guard let stripeCustomerId else {
            paymentErrorMessage = "Unable to load customer data."
            return
        }

        isLoadingPayment = true
        defer { isLoadingPayment = false }

        do {
            let paymentSheetContext = try await buildPaymentSheetContext(stripeCustomerId: stripeCustomerId)
            let initData = PaymentSheetInitData(
                mode: .paymentIntent(clientSecret: paymentSheetContext.paymentIntentClientSecret),
                publishableKey: paymentSheetContext.publishableKey,
                merchantDisplayName: "Demo Merchant",
                customer: .init(id: paymentSheetContext.customerId, ephemeralKey: paymentSheetContext.ephemeralKeySecret)
            )
            let result = try await PaymentSheetService.shared.present(with: initData)
            switch result {
            case .completed:
                paymentErrorMessage = nil
                await refreshPaymentMethods()
            case .canceled:
                paymentErrorMessage = "Payment canceled."
            case .failed(let message):
                paymentErrorMessage = message
            }
        } catch {
            paymentErrorMessage = error.localizedDescription
        }
#endif
    }

    private func buildPaymentSheetContext(stripeCustomerId: String) async throws -> StripePaymentService.PaymentSheetContext {
        let stripeService = StripePaymentService.shared
        let paymentIntent = try await stripeService.createPaymentIntent(
            shopId: "T60Soby70DmyhBhHw8bx", //This Is a `shopId` that's configured in Firebase for my business customer that is accepting payments.
            amountCents: 500,
            currency: "usd",
            description: "Demo payment",
            orderId: UUID().uuidString,
            stripeCustomerId: stripeCustomerId
        )
        return try await stripeService.buildPaymentSheetContext(
            stripeCustomerId: stripeCustomerId,
            paymentIntentClientSecret: paymentIntent.clientSecret
        )
    }

#if os(Android)
    private var androidPaymentButton: some View {
        Group {
            if let configuration = androidPaymentConfiguration {
                SimpleStripePaymentButton(configuration: configuration, buttonText: "Accept Payment", completion: handleAndroidPaymentResult)
                    .buttonStyle(.borderedProminent)
            } else {
                acceptPaymentFallbackButton
            }
        }
    }

    private var acceptPaymentFallbackButton: some View {
        Button {
            Task { await handleAcceptPayment() }
        } label: {
            acceptPaymentButtonLabel(isProcessing: isLoadingPayment)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoadingPayment)
    }

    @MainActor
    private func prepareAndroidPaymentConfiguration(triggeredByUser: Bool = false) async {
        if triggeredByUser {
            guard !isLoadingPayment else { return }
        } else if isLoadingPayment {
            return
        }
        guard let stripeCustomerId else {
            paymentErrorMessage = "Unable to load customer data."
            return
        }

        let previousClientSecret = androidPaymentConfiguration?.clientSecret

        if triggeredByUser {
            isLoadingPayment = true
            paymentErrorMessage = nil
            androidPaymentConfiguration = nil
        }

        defer {
            if triggeredByUser {
                isLoadingPayment = false
            }
        }

        do {
            let configuration = try await StripePaymentService.shared.buildAndroidPaymentConfiguration(
                stripeCustomerId: stripeCustomerId,
                shopId: "T60Soby70DmyhBhHw8bx", //This Is a `shopId` that's configured in Firebase for my business customer that is accepting payments.
                amountCents: 500,
                currency: "usd",
                description: "Demo payment",
                orderId: UUID().uuidString,
                merchantDisplayName: "Demo Merchant",
                allowsDelayedPaymentMethods: true,
                googlePayConfiguration: nil,
                primaryButtonLabel: nil,
                existingPaymentIntentClientSecret: previousClientSecret
            )
            androidPaymentConfiguration = configuration
        } catch {
            if triggeredByUser {
                paymentErrorMessage = error.localizedDescription
                androidPaymentConfiguration = nil
            } else {
                paymentErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func ensureAndroidPaymentConfiguration() async {
        guard androidPaymentConfiguration == nil else { return }
        await prepareAndroidPaymentConfiguration()
    }

    private func handleAndroidPaymentResult(_ result: StripePaymentResult) {
        Task { @MainActor in
            switch result {
            case .completed:
                paymentErrorMessage = nil
                androidPaymentConfiguration = nil
                await refreshPaymentMethods()
            case .canceled:
                paymentErrorMessage = "Payment canceled."
                androidPaymentConfiguration = nil
            case .failed(let error):
                paymentErrorMessage = error.localizedDescription
                androidPaymentConfiguration = nil
            }
            await ensureAndroidPaymentConfiguration()
        }
    }
#endif
}


