#if !os(Android)
import SkipFuseUI
import SkipStripe
import FireplaceModel
import FirebaseFirestore
@preconcurrency import FirebaseAuth

/// View for discovering and connecting to Stripe Terminal readers.
struct TerminalReaderView: View {
    @State var isDiscovering = false
    @State var discoveredReaders: [StripeTerminalReader] = []
    @State var errorMessage: String?
    @State var connectionStatus: TerminalConnectionStatus = .notConnected
    @State var selectedMethod: ReaderDiscoveryMethod = .bluetoothScan
    @State var useSimulated = false
    
    // Location setup state
    @State var currentLocationId: String? = nil
    @State var locationDisplayName = ""
    @State var addressLine1 = ""
    @State var addressCity = ""
    @State var addressState = ""
    @State var addressPostalCode = ""
    @State var isCreatingLocation = false
    @State var locationResult: String? = nil
    
    // Shop info for pre-filling
    var shopId: String?
    var shopName: String?
    var shopAddress: String?
    var shopCity: String?
    var shopState: String?
    var shopZip: String?
    var locationId: String?
    let onConnected: @MainActor @Sendable () -> Void
    let onDismiss: @MainActor @Sendable () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if connectionStatus == .connected {
                    connectedView
                } else if currentLocationId == nil {
                    // Step 1: Create a location first
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            Text("Set Up Location")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Locations must be set before connecting readers.")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Text("We've pre-filled your shop's address below. If anything is incorrect, change it here before saving.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            locationSetupView
                        }
                        .padding()
                    }
                } else {
                    // Step 2: Discover and connect readers
                    discoveryMethodPicker
                    
                    Divider()
                    
                    if isDiscovering {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Searching for readers...")
                                .font(.headline)
                            Text(discoveryMethodDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxHeight: .infinity)
                    } else if discoveredReaders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard.viewfinder")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No Readers Found")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(noReadersHint)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding()
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                Text("Select a Reader")
                                    .font(.headline)
                                    .padding(.top)
                                
                                ForEach(discoveredReaders) { reader in
                                    ReaderCard(reader: reader) {
                                        connectToReader(reader)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
                
                if connectionStatus == .connected {
                    // Disconnect button
                    Button(action: disconnectReader) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Disconnect Reader")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .padding()
                } else {
                    // Search button
                    Button(action: startDiscovery) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(isDiscovering ? "Searching..." : "Search for Readers")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.primaryColor)
                        .cornerRadius(12)
                    }
                    .disabled(isDiscovering)
                    .padding()
                    
                    #if DEBUG
                    Toggle("Use Simulated Reader", isOn: $useSimulated)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    #endif
                    
                    // Change Location button
                    if currentLocationId != nil {
                        Divider()
                        Button(action: {
                            currentLocationId = nil
                            locationResult = nil
                        }) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                Text("Change Location")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Terminal Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onDismiss()
                    }
                    .disabled(currentLocationId == nil)
                }
                if connectionStatus == .connected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onConnected()
                        }
                    }
                }
            }
        }
        .onAppear {
            // Initialize Terminal SDK with token provider if not already initialized
            if StripeTerminalManager.shared.connectionStatus == .notConnected {
                StripeTerminalManager.shared.initialize(tokenProvider: KioskTerminalService.shared)
            }
            connectionStatus = StripeTerminalManager.shared.connectionStatus
            if let reader = StripeTerminalManager.shared.connectedReader {
                discoveredReaders = [reader]
            }
            // Set initial location ID from shop
            if currentLocationId == nil, let locId = locationId {
                currentLocationId = locId
            }
            // Pre-fill location fields with shop info
            if locationDisplayName.isEmpty, let name = shopName { locationDisplayName = name }
            if addressLine1.isEmpty, let addr = shopAddress { addressLine1 = addr }
            if addressCity.isEmpty, let city = shopCity { addressCity = city }
            if addressState.isEmpty, let st = shopState { addressState = st }
            if addressPostalCode.isEmpty, let zip = shopZip { addressPostalCode = zip }
        }
    }
    
    // MARK: - Subviews
    
    var connectedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Reader Connected")
                .font(.title2)
                .fontWeight(.bold)
            if let reader = StripeTerminalManager.shared.connectedReader {
                Text(reader.label ?? reader.serialNumber)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text("Ready to accept payments")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
    
    var discoveryMethodPicker: some View {
        VStack(spacing: 8) {
            Text("Discovery Method")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("Method", selection: $selectedMethod) {
                Text("Bluetooth").tag(ReaderDiscoveryMethod.bluetoothScan)
                Text("Internet").tag(ReaderDiscoveryMethod.internet)
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Text("Tap to Pay").tag(ReaderDiscoveryMethod.localMobile)
                }
                #endif
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Text(supportedReadersDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding()
    }
    
    var supportedReadersDescription: String {
        switch selectedMethod {
        case .bluetoothScan:
            return "Supported readers: Stripe M2, Chipper 2X, WisePad 3\nThese portable readers connect via Bluetooth."
        case .internet:
            return "Supported readers: Stripe S700, WisePOS E\nThese countertop readers connect via WiFi or Ethernet."
        case .localMobile:
            return "Uses this device's built-in NFC.\nNo external reader needed."
        }
    }
    
    var discoveryMethodDescription: String {
        switch selectedMethod {
        case .bluetoothScan:
            return "Make sure your Stripe reader is powered on and Bluetooth is enabled on this device."
        case .internet:
            return "Searching for readers registered to your Stripe account on the same network."
        case .localMobile:
            return "Setting up Tap to Pay on this device."
        }
    }
    
    var noReadersHint: String {
        switch selectedMethod {
        case .bluetoothScan:
            return "Make sure your Stripe M2 (or compatible reader) is powered on, charged, and within Bluetooth range. Try pressing the power button on the reader."
        case .internet:
            return "Make sure your Stripe S700 or WisePOS E is connected to the internet and registered to your Stripe account."
        case .localMobile:
            return "Tap to Pay requires iPhone XS or later with iOS 16.4+."
        }
    }
    
    // MARK: - Actions
    
    func startDiscovery() {
        isDiscovering = true
        errorMessage = nil
        discoveredReaders = []
        
        // Cancel any previous discovery and wait before starting new one
        Task {
            StripeTerminalManager.shared.cancelDiscovery()
            
            // Wait for cancellation to complete
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            StripeTerminalManager.shared.discoverReaders(method: selectedMethod, simulated: useSimulated)
            
            // Poll for discovery results over 30 seconds, stop early if found
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let readers = StripeTerminalManager.shared.discoveredReaders
                if !readers.isEmpty {
                    await MainActor.run {
                        discoveredReaders = readers
                        isDiscovering = false
                    }
                    return
                }
            }
            
            await MainActor.run {
                isDiscovering = false
                discoveredReaders = StripeTerminalManager.shared.discoveredReaders
                if discoveredReaders.isEmpty {
                    errorMessage = "No readers found. \(noReadersHint)"
                }
            }
        }
    }
    
    func connectToReader(_ reader: StripeTerminalReader) {
        connectionStatus = .connecting
        errorMessage = nil
        
        StripeTerminalManager.shared.connectReader(reader, locationId: currentLocationId) { result in
            Task { @MainActor in
                switch result {
                case .success(let connectedReader):
                    self.connectionStatus = .connected
                    self.saveConnectedReaderInfo(reader: connectedReader)
                case .failure(let error):
                    self.connectionStatus = .notConnected
                    self.errorMessage = "Failed to connect: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func saveConnectedReaderInfo(reader: StripeTerminalReader) {
        guard let shopId = shopId, !shopId.isEmpty else { return }
        
        Task {
            do {
                try await Firestore.firestore().collection("shops").document(shopId).updateData([
                    "lastConnectedReaderSerial": reader.serialNumber,
                    "lastConnectedReaderLabel": (reader.label ?? reader.serialNumber) as Any
                ])
            } catch {
                print("Failed to save reader info: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnectReader() {
        StripeTerminalManager.shared.disconnectReader { error in
            Task { @MainActor in
                if let error = error {
                    self.errorMessage = "Disconnect failed: \(error.localizedDescription)"
                } else {
                    self.connectionStatus = .notConnected
                    self.discoveredReaders = []
                }
            }
        }
    }
    
    // MARK: - Location Setup
    
    var locationSetupView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Location Name", text: $locationDisplayName)
                .textFieldStyle(.roundedBorder)
            TextField("Address Line 1", text: $addressLine1)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("City", text: $addressCity)
                    .textFieldStyle(.roundedBorder)
                TextField("State", text: $addressState)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            TextField("Postal Code", text: $addressPostalCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            
            Button(action: createLocation) {
                HStack {
                    if isCreatingLocation {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isCreatingLocation ? (locationId != nil ? "Updating..." : "Creating...") : (locationId != nil ? "Update Location" : "Save Location"))
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(addressLine1.isEmpty || addressCity.isEmpty || addressState.isEmpty || addressPostalCode.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(isCreatingLocation || addressLine1.isEmpty || addressCity.isEmpty || addressState.isEmpty || addressPostalCode.isEmpty)
            
            if let result = locationResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.hasPrefix("Error") ? .red : .green)
            }
        }
    }
    
    func createLocation() {
        guard let shopId = shopId, !shopId.isEmpty else {
            locationResult = "Error: No shop ID"
            return
        }
        
        isCreatingLocation = true
        locationResult = nil
        let name = locationDisplayName.isEmpty ? (shopName ?? "Shop") : locationDisplayName
        
        let body: [String: Any] = [
            "shopId": shopId,
            "displayName": name,
            "line1": addressLine1,
            "city": addressCity,
            "state": addressState,
            "postalCode": addressPostalCode,
            "country": "US"
        ]
        
        Task {
            do {
                guard let user = Auth.auth().currentUser else {
                    await MainActor.run {
                        isCreatingLocation = false
                        locationResult = "Error: Not authenticated"
                    }
                    return
                }
                
                let idToken = try await user.getIDToken()
                guard let url = URL(string: "https://us-central1-YOUR-APP.cloudfunctions.net/createTerminalLocationV1") else {
                    await MainActor.run {
                        isCreatingLocation = false
                        locationResult = "Error: Invalid URL"
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let jsonData = try JSONSerialization.data(withJSONObject: ["data": body])
                request.httpBody = jsonData
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        isCreatingLocation = false
                        locationResult = "Error: Server returned an error"
                    }
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let locId = result["locationId"] as? String {
                    // Save to Firestore
                    try? await Firestore.firestore().collection("shops").document(shopId).updateData([
                        "terminalLocationId": locId
                    ])
                    
                    await MainActor.run {
                        isCreatingLocation = false
                        currentLocationId = locId
                        locationResult = "Location created successfully"
                    }
                } else {
                    await MainActor.run {
                        isCreatingLocation = false
                        locationResult = "Error: Unexpected response format"
                    }
                }
            } catch {
                await MainActor.run {
                    isCreatingLocation = false
                    locationResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Card view for displaying a discovered reader.
struct ReaderCard: View {
    let reader: StripeTerminalReader
    let onConnect: @MainActor @Sendable () -> Void
    
    var body: some View {
        Button(action: onConnect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reader.label ?? "Stripe Reader")
                        .font(.headline)
                    Text(reader.serialNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let deviceType = deviceTypeName {
                        Text(deviceType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let batteryLevel = reader.batteryLevel {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: batteryIcon(level: batteryLevel))
                            .foregroundColor(batteryColor(level: batteryLevel))
                        Text("\(Int(batteryLevel * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var deviceTypeName: String? {
        switch reader.deviceType {
        case .appleBuiltIn: return "Tap to Pay on iPhone"
        case .tapToPay: return "Tap to Pay on Android"
        case .stripeM2: return "Stripe M2"
        case .wisePad3: return "WisePad 3"
        case .chipper2X: return "Chipper 2X"
        default: return nil
        }
    }
    
    private func batteryIcon(level: Float) -> String {
        if reader.isCharging == true {
            return "battery.100.bolt"
        }
        if level > 0.75 { return "battery.100" }
        if level > 0.5 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }
    
    private func batteryColor(level: Float) -> Color {
        if level > 0.25 { return .green }
        return .red
    }
}
#endif
