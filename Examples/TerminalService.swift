#if !os(Android)
import Foundation
import SkipFuse
import SkipStripe
@preconcurrency import FirebaseAuth

/// Sendable box for wrapping a non-Sendable completion closure.
private final class SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Service for managing Stripe Terminal integration in the kiosk app.
public final class KioskTerminalService: StripeTerminalTokenProvider, @unchecked Sendable {
    public static let shared = KioskTerminalService()
    
    // Use deployed Cloud Functions for both DEBUG and RELEASE
    // This ensures physical devices can reach Stripe's test mode backend
    private let backendURL = "https://us-central1-YOUR-APP.cloudfunctions.net"
    
    private init() {}
    
    /// Fetch a connection token from the backend.
    public func fetchConnectionToken(completion: @escaping (String?, Error?) -> Void) {
        let boxed = SendableBox(completion)
        let url = backendURL
        
        Task.detached {
            let result = await KioskTerminalService.performFetch(backendURL: url)
            boxed.value(result.0, result.1)
        }
    }
    
    /// Static async helper — no instance captures needed.
    private static func performFetch(backendURL: String) async -> (String?, Error?) {
        guard let user = Auth.auth().currentUser else {
            return (nil, NSError(domain: "TerminalService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
        }
        
        do {
            let idToken = try await user.getIDToken()
            guard let url = URL(string: "\(backendURL)/createTerminalConnectionToken") else {
                return (nil, NSError(domain: "TerminalService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (nil, NSError(domain: "TerminalService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch connection token"]))
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let secret = json["secret"] as? String {
                return (secret, nil)
            } else {
                return (nil, NSError(domain: "TerminalService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
            }
        } catch {
            return (nil, error)
        }
    }
}
#endif

