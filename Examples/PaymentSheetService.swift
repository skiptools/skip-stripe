import Foundation

// MARK: - Shared Types

public struct PaymentSheetInitData: Sendable {
    public enum Mode: Sendable {
        case paymentIntent(clientSecret: String)
        case setupIntent(clientSecret: String)
    }

    public struct Customer: Sendable {
        public let id: String
        public let ephemeralKey: String

        public init(id: String, ephemeralKey: String) {
            self.id = id
            self.ephemeralKey = ephemeralKey
        }
    }

    public let mode: Mode
    public let publishableKey: String
    public let merchantDisplayName: String
    public let customer: Customer?
    public let allowsDelayedPaymentMethods: Bool

    public init(
        mode: Mode,
        publishableKey: String,
        merchantDisplayName: String,
        customer: Customer? = nil,
        allowsDelayedPaymentMethods: Bool = true
    ) {
        self.mode = mode
        self.publishableKey = publishableKey
        self.merchantDisplayName = merchantDisplayName
        self.customer = customer
        self.allowsDelayedPaymentMethods = allowsDelayedPaymentMethods
    }
}

public enum PaymentSheetOutcome: Sendable, Equatable {
    case completed
    case canceled
    case failed(String)
}

public protocol PaymentSheetPresenting: AnyObject {
    func present(with data: PaymentSheetInitData) async throws -> PaymentSheetOutcome
}

@MainActor
public final class PaymentSheetService {
    public static let shared = PaymentSheetService()

    private init() {}

    public func present(with data: PaymentSheetInitData) async throws -> PaymentSheetOutcome {
        #if canImport(UIKit)
        return try await iOSPaymentSheetPresenter.shared.present(with: data)
        #else
        return .failed("Stripe PaymentSheet is not available on this platform yet.")
        #endif
    }
}

// MARK: - iOS Implementation

#if canImport(UIKit)
import UIKit
import StripePaymentSheet

@MainActor
fileprivate final class iOSPaymentSheetPresenter: PaymentSheetPresenting {
    static let shared = iOSPaymentSheetPresenter()
    private init() {}

    private var paymentSheet: PaymentSheet?

    func present(with data: PaymentSheetInitData) async throws -> PaymentSheetOutcome {
        STPAPIClient.shared.publishableKey = data.publishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = data.merchantDisplayName
        configuration.allowsDelayedPaymentMethods = data.allowsDelayedPaymentMethods

        if let customer = data.customer {
            configuration.customer = .init(id: customer.id, ephemeralKeySecret: customer.ephemeralKey)
        }

        switch data.mode {
        case .paymentIntent(let clientSecret):
            paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        case .setupIntent(let clientSecret):
            paymentSheet = PaymentSheet(setupIntentClientSecret: clientSecret, configuration: configuration)
        }

        guard let presenter = Self.topMostViewController() else {
            throw NSError(domain: "PaymentSheetService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No presenter view controller available"])
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.paymentSheet?.present(from: presenter) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .completed)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    private static func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?
        .rootViewController) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topMostViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController, let selected = tabBarController.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
#endif
