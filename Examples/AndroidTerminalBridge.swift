#if os(Android)
import Foundation
import SkipFuse
import SkipStripe

// MARK: - Android Terminal Bridge
// Calls the bridged SkipStripe API directly from native Swift.
// SkipStripe has bridging:true, so StripeTerminalManager and related types
// are accessible from native Swift on Android.
// The token provider (URLConnectionTokenProvider) lives in SkipStripe's transpiled layer
// where it can call Firebase Auth + HTTP Kotlin APIs directly.

/// Bridge class that wraps StripeTerminalManager for Android.
public class TerminalBridge: @unchecked Sendable {
    public static let shared = TerminalBridge()
    
    public private(set) var isInitialized: Bool = false
    public private(set) var isConnected: Bool = false
    public private(set) var connectedReaderName: String? = nil
    public private(set) var isDiscovering: Bool = false
    public private(set) var discoveredReaderCount: Int = 0
    public private(set) var lastError: String? = nil
    public private(set) var discoveredReaderIds: [String] = []
    public private(set) var discoveredReaderNames: [String] = []
    
    public var isUpdatingFirmware: Bool {
        StripeTerminalManager.shared.isUpdatingFirmware
    }
    
    public var firmwareUpdateProgress: Double {
        StripeTerminalManager.shared.firmwareUpdateProgress
    }
    
    public var firmwareUpdatePercent: Int {
        Int(StripeTerminalManager.shared.firmwareUpdateProgress * 100.0)
    }
    
    public var supportsTapToPay: Bool {
        do {
            let adapterStatics = try AnyDynamicObject(forStaticsOfClassName: "android.nfc.NfcAdapter")
            let processInfoStatics = try AnyDynamicObject(forStaticsOfClassName: "skip.foundation.ProcessInfo")
            let processInfo: AnyDynamicObject = processInfoStatics.processInfo!
            let context: AnyDynamicObject = processInfo.androidContext!
            let adapter: AnyDynamicObject? = try adapterStatics.getDefaultAdapter(context)
            return adapter != nil
        } catch {
            return false
        }
    }
    
    private init() {}
    
    public func initialize() {
        guard !isInitialized else { return }
        let provider = URLConnectionTokenProvider(backendURL: "https://us-central1-YOUR-APP.cloudfunctions.net")
        StripeTerminalManager.shared.initialize(tokenProvider: provider)
        isInitialized = true
    }
    
    public func startDiscovery(method: String, simulated: Bool) {
        guard isInitialized else {
            lastError = "Terminal not initialized"
            return
        }
        // Cancel any previous discovery first
        StripeTerminalManager.shared.cancelDiscovery()
        
        isDiscovering = true
        lastError = nil
        discoveredReaderIds = []
        discoveredReaderNames = []
        discoveredReaderCount = 0
        
        let discoveryMethod: ReaderDiscoveryMethod
        switch method {
        case "internet": discoveryMethod = .internet
        case "tapToPay": discoveryMethod = .localMobile
        default: discoveryMethod = .bluetoothScan
        }
        
        StripeTerminalManager.shared.discoverReaders(method: discoveryMethod, simulated: simulated)
        
        // Poll for discovered readers
        pollForReaders(pollCount: 0)
    }
    
    private func pollForReaders(pollCount: Int) {
        guard pollCount < 30, isDiscovering else {
            isDiscovering = false
            if discoveredReaderCount == 0 {
                lastError = "No readers found. Make sure the reader is powered on and nearby."
            }
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            let readers = StripeTerminalManager.shared.discoveredReaders
            self.discoveredReaderCount = readers.count
            self.discoveredReaderIds = readers.map { $0.serialNumber }
            self.discoveredReaderNames = readers.map { $0.label ?? $0.serialNumber }
            
            if readers.isEmpty && self.isDiscovering {
                self.pollForReaders(pollCount: pollCount + 1)
            } else {
                self.isDiscovering = false
            }
        }
    }
    
    public func stopDiscovery() {
        isDiscovering = false
        StripeTerminalManager.shared.cancelDiscovery()
    }
    
    public func connectReader(atIndex index: Int, locationId: String?) {
        let readers = StripeTerminalManager.shared.discoveredReaders
        guard index >= 0 && index < readers.count else {
            lastError = "Invalid reader index"
            return
        }
        let reader = readers[index]
        StripeTerminalManager.shared.connectReader(reader, locationId: locationId) { [weak self] result in
            switch result {
            case .success(let connectedReader):
                self?.isConnected = true
                self?.connectedReaderName = connectedReader.label ?? connectedReader.serialNumber
            case .failure(let error):
                self?.isConnected = false
                self?.lastError = error.localizedDescription
            }
        }
    }
    
    public func disconnectReader() {
        StripeTerminalManager.shared.disconnectReader { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.lastError = error.localizedDescription
                } else {
                    self.isConnected = false
                    self.connectedReaderName = nil
                }
            }
        }
    }
    
    public func collectPayment(amountInCents: Int, currency: String, completion: @escaping (Bool, String?) -> Void) {
        StripeTerminalManager.shared.collectPayment(amount: amountInCents, currency: currency) { result in
            switch result {
            case .success(let paymentIntentId):
                completion(true, paymentIntentId)
            case .failure(let error):
                completion(false, error.localizedDescription)
            }
        }
    }
    
    public func cancelPayment() {
        StripeTerminalManager.shared.cancelPayment()
    }
    
    // MARK: - Admin Setup
    
    public func createLocation(shopId: String, displayName: String, addressLine1: String, city: String, state: String, postalCode: String, country: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        let jsonBody = """
        {"data":{"shopId":"\(shopId)","displayName":"\(displayName)","address":{"line1":"\(addressLine1)","city":"\(city)","state":"\(state)","postal_code":"\(postalCode)","country":"\(country)"}}}
        """
        
        callCloudFunction(
            url: "https://us-central1-YOUR-APP.cloudfunctions.net/createTerminalLocationV1",
            jsonBody: jsonBody
        ) { success, responseBody in
            if success, let body = responseBody {
                // Parse locationId from response: {"result":{"locationId":"tml_xxx"}}
                if let range = body.range(of: "\"locationId\":\"") {
                    let start = range.upperBound
                    if let end = body[start...].firstIndex(of: "\"") {
                        let locationId = String(body[start..<end])
                        completion(true, locationId)
                        return
                    }
                }
                completion(false, "Could not parse location ID from response")
            } else {
                completion(false, responseBody ?? "Failed to create location")
            }
        }
    }
    
    public func registerReader(shopId: String, registrationCode: String, label: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        let jsonBody = """
        {"data":{"shopId":"\(shopId)","registrationCode":"\(registrationCode)","label":"\(label)"}}
        """
        
        callCloudFunction(
            url: "https://us-central1-YOUR-APP.cloudfunctions.net/registerTerminalReaderV1",
            jsonBody: jsonBody
        ) { success, responseBody in
            if success, let body = responseBody {
                if let range = body.range(of: "\"serialNumber\":\"") {
                    let start = range.upperBound
                    if let end = body[start...].firstIndex(of: "\"") {
                        let serial = String(body[start..<end])
                        completion(true, "Reader registered: \(serial)")
                        return
                    }
                }
                completion(true, "Reader registered")
            } else {
                completion(false, responseBody ?? "Failed to register reader")
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Call a Cloud Function using AuthenticatedCloudFunctionCaller from the bridged SkipStripe module.
    /// Firebase Auth + HTTP runs in the transpiled Kotlin layer where it works natively.
    private func callCloudFunction(url: String, jsonBody: String, completion: @escaping @Sendable (Bool, String?) -> Void) {
        AuthenticatedCloudFunctionCaller.shared.call(url: url, jsonBody: jsonBody) { success, responseBody in
            completion(success, responseBody)
        }
    }
}
#endif
