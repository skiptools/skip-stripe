import Foundation
import SkipFuse


#if os(Android)
@preconcurrency import SkipFirebaseAuth
import SkipStripe
#else
@preconcurrency import FirebaseAuth
import Stripe
#endif

struct StripePaymentService {
    static let shared = StripePaymentService()

    struct Configuration {
        /// Update this to match the deployed Cloud Functions base URL.
        static let baseURLString = "https://us-central1-yourapp.cloudfunctions.net" // This is the endpoint that I use for Firebase. If you are using a different endpoint, see Stripe's Integration Guide for how to set up webhooks. 
    }

    enum ServiceError: LocalizedError {
        case notAuthenticated
        case missingBaseURL
        case invalidResponse
        case callable(String)
        case networkFailure

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You must be signed in to submit a payment."
            case .missingBaseURL:
                return "Stripe payment service base URL is not configured."
            case .invalidResponse:
                return "Unexpected response from payment service."
            case .callable(let message):
                return message
            case .networkFailure:
                return "Unable to reach the payment service. Check your connection and try again."
            }
        }
    }

    struct PaymentIntentResponse: Decodable {
        let paymentIntentId: String
        let clientSecret: String
        let amount: Int
        let currency: String
        let applicationFeeAmount: Int?
        let livemode: Bool
    }

    struct CreateCustomerResponse: Decodable {
        let stripeCustomerId: String
        let created: Bool
    }

    struct EphemeralKeyResponse: Decodable {
        let id: String
        let object: String
        let secret: String
        let created: TimeInterval
        let livemode: Bool
        let expires: TimeInterval
        let associatedObjects: [AssociatedObject]

        struct AssociatedObject: Decodable {
            let type: String
            let id: String
        }
    }

    struct StripeConfigResponse: Decodable {
        let publishableKey: String
        let paymentMode: String?
        let platformFeeBps: Int?
    }

    struct PaymentMethodListResponse: Decodable {
        let paymentMethods: [StripePaymentMethod]
    }

    struct StripePaymentMethod: Decodable, Identifiable {
        let id: String
        let type: String
        let card: CardDetails?

        struct CardDetails: Decodable {
            let brand: String?
            let expMonth: Int?
            let expYear: Int?
            let last4: String?
        }
    }

    struct PaymentSheetContext {
        let publishableKey: String
        let customerId: String
        let ephemeralKeySecret: String
        let paymentIntentClientSecret: String
    }

    private var baseURL: URL? {
        URL(string: Configuration.baseURLString)
    }

    func ensureCustomer() async throws -> CreateCustomerResponse {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }
        log("ensureCustomer: starting for uid=\(user.uid)")
        let idToken = try await user.getIDToken()
        let response: CreateCustomerResponse = try await invokeCallable(
            "createStripeCustomerV1",
            payload: [:],
            idToken: idToken,
            baseURL: baseURL
        )
        log("ensureCustomer: success created=\(response.created) stripeCustomerId=\(response.stripeCustomerId)")
        return response
    }

    func createEphemeralKey(stripeCustomerId: String, apiVersion: String = "2025-08-27.basil") async throws -> EphemeralKeyResponse {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }
        log("createEphemeralKey: starting for customer=\(stripeCustomerId) apiVersion=\(apiVersion)")
        let idToken = try await user.getIDToken()
        let payload: [String: Any] = [
            "stripeCustomerId": stripeCustomerId,
            "apiVersion": apiVersion
        ]
        let response: EphemeralKeyResponse = try await invokeCallable(
            "createStripeEphemeralKeyV1",
            payload: payload,
            idToken: idToken,
            baseURL: baseURL
        )
        log("createEphemeralKey: success keyId=\(response.id) expires=\(response.expires)")
        return response
    }

    func fetchStripeConfig() async throws -> StripeConfigResponse {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }
        log("fetchStripeConfig: starting for uid=\(user.uid)")
        let idToken = try await user.getIDToken()
        let response: StripeConfigResponse = try await invokeCallable(
            "getStripeConfigV2",
            payload: [:],
            idToken: idToken,
            baseURL: baseURL
        )
        log("fetchStripeConfig: success publishableKey=\(response.publishableKey.prefix(8))… paymentMode=\(response.paymentMode ?? "nil")")
        return response
    }

    func listPaymentMethods(stripeCustomerId: String, type: String = "card") async throws -> [StripePaymentMethod] {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }
        let idToken = try await user.getIDToken()
        let payload: [String: Any] = [
            "stripeCustomerId": stripeCustomerId,
            "type": type
        ]
        log("listPaymentMethods: starting for customer=\(stripeCustomerId) type=\(type)")
        let response: PaymentMethodListResponse = try await invokeCallable(
            "listStripePaymentMethodsV1",
            payload: payload,
            idToken: idToken,
            baseURL: baseURL
        )
        log("listPaymentMethods: success count=\(response.paymentMethods.count)")
        return response.paymentMethods
    }

    func detachPaymentMethod(stripeCustomerId: String, paymentMethodId: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }
        log("detachPaymentMethod: starting customer=\(stripeCustomerId) paymentMethodId=\(paymentMethodId)")
        let idToken = try await user.getIDToken()
        let payload: [String: Any] = [
            "stripeCustomerId": stripeCustomerId,
            "paymentMethodId": paymentMethodId
        ]
        struct DetachResponse: Decodable { let detachedPaymentMethodId: String }
        _ = try await invokeCallable(
            "detachStripePaymentMethodV1",
            payload: payload,
            idToken: idToken,
            baseURL: baseURL
        ) as DetachResponse
        log("detachPaymentMethod: success detachedId=\(paymentMethodId)")
    }

    func buildPaymentSheetContext(
        stripeCustomerId: String,
        paymentIntentClientSecret: String
    ) async throws -> PaymentSheetContext {
        log("buildPaymentSheetContext: starting customer=\(stripeCustomerId)")
        let config = try await fetchStripeConfig()
        guard !config.publishableKey.isEmpty else {
            log("buildPaymentSheetContext: publishable key missing")
            throw ServiceError.invalidResponse
        }
        let ephemeralKey = try await createEphemeralKey(stripeCustomerId: stripeCustomerId)
        log("buildPaymentSheetContext: success ephemeralKeyId=\(ephemeralKey.id)")
        return PaymentSheetContext(
            publishableKey: config.publishableKey,
            customerId: stripeCustomerId,
            ephemeralKeySecret: ephemeralKey.secret,
            paymentIntentClientSecret: paymentIntentClientSecret
        )
    }

#if os(Android)
    /// Builds a `StripePaymentConfiguration` suitable for presenting the Stripe Payment Sheet on Android via SkipStripe.
    /// - Parameters:
    ///   - stripeCustomerId: The Stripe customer identifier associated with the authenticated Firebase user.
    ///   - shopId: Identifier of the shop to bill in the demo backend.
    ///   - amountCents: Payment amount in the smallest currency unit.
    ///   - currency: ISO currency code for the payment intent (default `usd`).
    ///   - description: Optional description forwarded to Stripe.
    ///   - orderId: Optional order identifier.
    ///   - receiptEmail: Optional receipt email address.
    ///   - merchantDisplayName: Merchant name shown in the payment sheet.
    ///   - allowsDelayedPaymentMethods: Whether to allow delayed payment methods (default `true`).
    ///   - googlePayConfiguration: Optional Google Pay configuration to attach to the sheet.
    ///   - primaryButtonLabel: Optional override for the primary button label inside the sheet.
    /// - Returns: Configured `StripePaymentConfiguration` ready for `SimpleStripePaymentButton` / `StripePaymentButton`.
    func buildAndroidPaymentConfiguration(
        stripeCustomerId: String,
        shopId: String,
        amountCents: Int,
        currency: String = "usd",
        description: String? = nil,
        orderId: String? = nil,
        receiptEmail: String? = nil,
        merchantDisplayName: String,
        allowsDelayedPaymentMethods: Bool = true,
        googlePayConfiguration: StripePaymentConfiguration.GooglePayConfiguration? = nil,
        primaryButtonLabel: String? = nil,
        existingPaymentIntentClientSecret: String? = nil
    ) async throws -> StripePaymentConfiguration {
        let paymentIntentClientSecret: String

        if let existingPaymentIntentClientSecret, !existingPaymentIntentClientSecret.isEmpty {
            paymentIntentClientSecret = existingPaymentIntentClientSecret
        } else {
            let paymentIntent = try await createPaymentIntent(
                shopId: shopId,
                amountCents: amountCents,
                currency: currency,
                description: description,
                orderId: orderId,
                receiptEmail: receiptEmail,
                stripeCustomerId: stripeCustomerId
            )
            paymentIntentClientSecret = paymentIntent.clientSecret
        }

        let context = try await buildPaymentSheetContext(
            stripeCustomerId: stripeCustomerId,
            paymentIntentClientSecret: paymentIntentClientSecret
        )

        return makeAndroidPaymentConfiguration(
            context: context,
            merchantDisplayName: merchantDisplayName,
            allowsDelayedPaymentMethods: allowsDelayedPaymentMethods,
            googlePayConfiguration: googlePayConfiguration,
            primaryButtonLabel: primaryButtonLabel
        )
    }

    private func makeAndroidPaymentConfiguration(
        context: PaymentSheetContext,
        merchantDisplayName: String,
        allowsDelayedPaymentMethods: Bool,
        googlePayConfiguration: StripePaymentConfiguration.GooglePayConfiguration?,
        primaryButtonLabel: String?
    ) -> StripePaymentConfiguration {
        var configuration = StripePaymentConfiguration(
            publishableKey: context.publishableKey,
            merchantName: merchantDisplayName,
            customerID: context.customerId,
            ephemeralKeySecret: context.ephemeralKeySecret,
            clientSecret: context.paymentIntentClientSecret
        )
        configuration.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
        configuration.googlePay = googlePayConfiguration
        configuration.primaryButtonLabel = primaryButtonLabel
        return configuration
    }
#endif

    func createPaymentIntent(
        shopId: String,
        amountCents: Int,
        currency: String = "usd",
        description: String? = nil,
        orderId: String? = nil,
        receiptEmail: String? = nil,
        stripeCustomerId: String? = nil
    ) async throws -> PaymentIntentResponse {
        guard let user = Auth.auth().currentUser else {
            throw ServiceError.notAuthenticated
        }
        guard let baseURL else {
            throw ServiceError.missingBaseURL
        }

        var payload: [String: Any] = [
            "shopId": shopId,
            "amountCents": amountCents,
            "currency": currency.lowercased()
        ]
        if let description, !description.isEmpty {
            payload["description"] = description
        }
        if let orderId, !orderId.isEmpty {
            payload["orderId"] = orderId
        }
        if let receiptEmail, !receiptEmail.isEmpty {
            payload["receiptEmail"] = receiptEmail
        }
        if let stripeCustomerId, !stripeCustomerId.isEmpty {
            payload["stripeCustomerId"] = stripeCustomerId
        }

        let idToken = try await user.getIDToken()
        log("createPaymentIntent: starting shop=\(shopId) amountCents=\(amountCents) currency=\(currency) stripeCustomerId=\(stripeCustomerId ?? "nil")")
        let response: PaymentIntentResponse = try await invokeCallable(
            "createStripePaymentIntentV1",
            payload: payload,
            idToken: idToken,
            baseURL: baseURL
        )
        log("createPaymentIntent: success intentId=\(response.paymentIntentId) amount=\(response.amount) livemode=\(response.livemode)")
        return response
    }

    // MARK: - Internal

    private func invokeCallable<T: Decodable>(
        _ name: String,
        payload: [String: Any],
        idToken: String,
        baseURL: URL
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(name))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["data": payload]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            logNetworkRequest(name: name, urlRequest: request, payload: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            logNetworkResponse(name: name, response: response, data: data)
            guard let httpResponse = response as? HTTPURLResponse else {
                log("invokeCallable(\(name)): missing HTTPURLResponse")
                throw ServiceError.invalidResponse
            }

            if !(200..<300).contains(httpResponse.statusCode) {
                if let callableError = try? decodeCallableError(from: data) {
                    log("invokeCallable(\(name)): callable error status=\(callableError.status) message=\(callableError.message)")
                    throw ServiceError.callable(callableError.message)
                }
                log("invokeCallable(\(name)): invalid response status=\(httpResponse.statusCode)")
                throw ServiceError.invalidResponse
            }

            if let callableError = try? decodeCallableError(from: data) {
                log("invokeCallable(\(name)): error envelope status=\(callableError.status) message=\(callableError.message)")
                throw ServiceError.callable(callableError.message)
            }

            let envelope: CallableEnvelope<T> = try decodeCallableResponse(from: data)
            return envelope.result
        } catch let serviceError as ServiceError {
            log("invokeCallable(\(name)): service error=\(serviceError)")
            throw serviceError
        } catch {
            log("invokeCallable(\(name)): network failure error=\(error.localizedDescription)")
            throw ServiceError.networkFailure
        }
    }

    private func decodeCallableResponse<T: Decodable>(from data: Data) throws -> CallableEnvelope<T> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CallableEnvelope<T>.self, from: data)
    }

    private func decodeCallableError(from data: Data) throws -> CallableErrorEnvelope.CallableError {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(CallableErrorEnvelope.self, from: data)
        return envelope.error
    }

#if os(iOS)
    private func log(_ message: String) {
        print("[StripePaymentService] \(message)")
    }

    private func logNetworkRequest(name: String, urlRequest: URLRequest, payload: [String: Any]) {
        var safePayload = payload
        if safePayload["stripeCustomerId"] == nil {
            // No-op; placeholder to show payload even when empty.
        }
        let bodyDescription: String
        if let body = try? JSONSerialization.data(withJSONObject: ["data": safePayload], options: [.prettyPrinted]),
           let bodyString = String(data: body, encoding: .utf8) {
            bodyDescription = bodyString
        } else {
            bodyDescription = String(describing: safePayload)
        }

        print("[StripePaymentService] → Request name=\(name) url=\(urlRequest.url?.absoluteString ?? "nil") payload=\(bodyDescription)")
    }

    private func logNetworkResponse(name: String, response: URLResponse, data: Data) {
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[StripePaymentService] ← Response name=\(name) (non HTTP) bytes=\(data.count)")
            return
        }

        let preview: String
        if let text = String(data: data, encoding: .utf8) {
            preview = text
        } else {
            preview = "<binary>"
        }

        print("[StripePaymentService] ← Response name=\(name) status=\(httpResponse.statusCode) bytes=\(data.count) body=\(preview)")
    }
#else
    private func log(_ message: String) {}
    private func logNetworkRequest(name: String, urlRequest: URLRequest, payload: [String: Any]) {}
    private func logNetworkResponse(name: String, response: URLResponse, data: Data) {}
#endif
}

private struct CallableEnvelope<T: Decodable>: Decodable {
    let result: T
}

private struct CallableErrorEnvelope: Decodable {
    struct CallableError: Decodable {
        let status: String
        let message: String
    }

    let error: CallableError
}
