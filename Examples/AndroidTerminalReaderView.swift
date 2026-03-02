import SkipFuseUI
#if os(Android)
import SkipFirebaseFirestore
#else
import FirebaseFirestore
#endif

#if os(Android)
/// Android Terminal reader discovery and connection view.
/// Matches iOS TerminalReaderView layout with discovery method picker.
struct AndroidTerminalReaderView: View {
    @State var isDiscovering = false
    @State var isConnecting = false
    @State var isDisconnecting = false
    @State var errorMessage: String?
    @State var selectedMethod: String = "bluetooth"
    @State var useSimulated = false
    @State var showAdminSetup = false
    @State var registrationCode = ""
    @State var readerLabel = ""
    @State var isRegistering = false
    @State var registrationResult: String?
    @State var locationDisplayName = ""
    @State var addressLine1 = ""
    @State var addressCity = ""
    @State var addressState = ""
    @State var addressPostalCode = ""
    @State var isCreatingLocation = false
    @State var locationResult: String?
    @State var locationId: String? = nil
    
    let shopId: String
    let shopName: String
    let shopAddress: String?
    let shopCity: String?
    let shopState: String?
    let shopZip: String?
    let existingLocationId: String?
    let onConnected: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if TerminalBridge.shared.isConnected {
                    connectedView
                } else if isConnecting {
                    VStack(spacing: 16) {
                        Spacer()
                        if TerminalBridge.shared.isUpdatingFirmware {
                            ProgressView(value: Double(TerminalBridge.shared.firmwareUpdateProgress))
                                .progressViewStyle(.linear)
                                .frame(width: 200)
                            Text("Updating Reader Firmware")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("\(TerminalBridge.shared.firmwareUpdatePercent)%")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.blue)
                            Text("Please keep the reader nearby.\nThis may take a few minutes.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            ProgressView()
                                .scaleEffect(2.0)
                            Text("Connecting to Reader...")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Please wait while connecting.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                } else if locationId == nil {
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
                            
                            adminSetupLocationView
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
                            
                            if TerminalBridge.shared.discoveredReaderCount > 0 {
                                readerList
                            }
                            
                            Button(action: stopDiscovery) {
                                Text("Cancel Search")
                                    .foregroundColor(.red)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .frame(maxHeight: .infinity)
                    } else if TerminalBridge.shared.discoveredReaderCount == 0 {
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
                                readerList
                            }
                            .padding()
                        }
                    }
                }
                
                if let error = errorMessage ?? TerminalBridge.shared.lastError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
                
                if TerminalBridge.shared.isConnected {
                    Button(action: {
                        isDisconnecting = true
                        TerminalBridge.shared.disconnectReader()
                        // Poll to check if disconnected
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkDisconnectStatus()
                        }
                    }) {
                        HStack {
                            if isDisconnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .tint(.white)
                                    .scaleEffect(0.8)
                                Text("Disconnecting...")
                            } else {
                                Image(systemName: "xmark.circle")
                                Text("Disconnect Reader")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isDisconnecting ? Color.gray : Color.red)
                        .cornerRadius(12)
                    }
                    .disabled(isDisconnecting)
                    .padding()
                } else {
                    Button(action: startDiscovery) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(isDiscovering ? "Searching..." : "Search for Readers")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
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
                }
                
                Divider()
                
                // Change Location button
                if locationId != nil {
                    Button(action: {
                        locationId = nil
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
                
                // Admin Setup Section
                Button(action: { showAdminSetup.toggle() }) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Admin: Register New Reader")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: showAdminSetup ? "chevron.up" : "chevron.down")
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                if showAdminSetup {
                    adminSetupView
                }
            }
            .navigationTitle("Terminal Setup")
            .onAppear {
                if locationId == nil, let existing = existingLocationId {
                    locationId = existing
                }
                // Pre-fill location fields with shop info
                if locationDisplayName.isEmpty { locationDisplayName = shopName }
                if addressLine1.isEmpty, let addr = shopAddress { addressLine1 = addr }
                if addressCity.isEmpty, let city = shopCity { addressCity = city }
                if addressState.isEmpty, let st = shopState { addressState = st }
                if addressPostalCode.isEmpty, let zip = shopZip { addressPostalCode = zip }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                        .disabled(locationId == nil)
                }
                if TerminalBridge.shared.isConnected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onConnected() }
                    }
                }
            }
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
            if let name = TerminalBridge.shared.connectedReaderName {
                Text(name)
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
                Text("Bluetooth").tag("bluetooth")
                Text("Internet").tag("internet")
                if TerminalBridge.shared.supportsTapToPay {
                    Text("Tap to Pay").tag("tapToPay")
                }
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
        case "internet":
            return "Supported readers: Stripe S700, WisePOS E\nThese countertop readers connect via WiFi or Ethernet."
        case "tapToPay":
            return "Uses this device's built-in NFC.\nNo external reader needed."
        default:
            return "Supported readers: Stripe M2, Chipper 2X, WisePad 3\nThese portable readers connect via Bluetooth."
        }
    }
    
    var readerList: some View {
        VStack(spacing: 8) {
            if locationId == nil {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Create a Location first (Admin section below) before connecting a reader.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            ForEach(0..<TerminalBridge.shared.discoveredReaderCount, id: \.self) { index in
                Button(action: {
                    guard locationId != nil else {
                        errorMessage = "Please create a Location first using the Admin section below."
                        return
                    }
                    isDiscovering = false
                    isConnecting = true
                    errorMessage = nil
                    TerminalBridge.shared.connectReader(atIndex: index, locationId: locationId)
                    // Poll for connection completion
                    pollConnectionState()
                }) {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            if index < TerminalBridge.shared.discoveredReaderNames.count {
                                Text(TerminalBridge.shared.discoveredReaderNames[index])
                                    .font(.headline)
                            } else {
                                Text("Reader \(index + 1)")
                                    .font(.headline)
                            }
                            if index < TerminalBridge.shared.discoveredReaderIds.count {
                                Text(TerminalBridge.shared.discoveredReaderIds[index])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
            }
        }
    }
    
    var adminSetupLocationView: some View {
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
                    }
                    Text(isCreatingLocation ? (existingLocationId != nil ? "Updating..." : "Creating...") : (existingLocationId != nil ? "Update Location" : "Save Location"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
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
    
    var adminSetupView: some View {
        VStack(spacing: 16) {
            // Location Creation
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Create Terminal Location")
                    .font(.headline)
                Text("Required before registering an Internet-connected reader (S700, WisePOS E).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                        }
                        Text(isCreatingLocation ? (existingLocationId != nil ? "Updating..." : "Creating...") : (existingLocationId != nil ? "Update Location" : "Create Location"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isCreatingLocation || addressLine1.isEmpty || addressCity.isEmpty || addressState.isEmpty || addressPostalCode.isEmpty)
                
                if let result = locationResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.hasPrefix("Error") ? .red : .green)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Reader Registration
            VStack(alignment: .leading, spacing: 8) {
                Text("2. Register Reader")
                    .font(.headline)
                Text("Enter the registration code displayed on the reader's screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Registration Code", text: $registrationCode)
                    .textFieldStyle(.roundedBorder)
                TextField("Reader Label (optional)", text: $readerLabel)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: registerReader) {
                    HStack {
                        if isRegistering {
                            ProgressView()
                        }
                        Text(isRegistering ? "Registering..." : "Register Reader")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isRegistering || registrationCode.isEmpty)
                
                if let result = registrationResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.hasPrefix("Error") ? .red : .green)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    // MARK: - Computed Properties
    
    var discoveryMethodDescription: String {
        switch selectedMethod {
        case "internet":
            return "Searching for readers registered to your Stripe account on the same network."
        case "tapToPay":
            return "Setting up Tap to Pay on this device."
        default:
            return "Make sure your Stripe reader is powered on and Bluetooth is enabled on this device."
        }
    }
    
    var noReadersHint: String {
        switch selectedMethod {
        case "internet":
            return "Make sure your Stripe S700 or WisePOS E is connected to the internet and registered to your Stripe account."
        case "tapToPay":
            return "Tap to Pay requires a compatible Android device with NFC enabled."
        default:
            return "Make sure your Stripe M2 (or compatible reader) is powered on, charged, and within Bluetooth range. Try pressing the power button on the reader."
        }
    }
    
    // MARK: - Actions
    
    func startDiscovery() {
        isDiscovering = true
        errorMessage = nil
        TerminalBridge.shared.startDiscovery(method: selectedMethod, simulated: useSimulated)
        
        // Poll bridge state to detect when discovery finishes
        pollBridgeState()
    }
    
    func stopDiscovery() {
        isDiscovering = false
        TerminalBridge.shared.stopDiscovery()
    }
    
    private func pollConnectionState() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if TerminalBridge.shared.isConnected {
                isConnecting = false
                return
            }
            if let error = TerminalBridge.shared.lastError {
                isConnecting = false
                errorMessage = error
                return
            }
            if isConnecting {
                pollConnectionState()
            }
        }
    }
    
    private func pollBridgeState() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !TerminalBridge.shared.isDiscovering {
                isDiscovering = false
                if TerminalBridge.shared.discoveredReaderCount == 0 {
                    errorMessage = TerminalBridge.shared.lastError ?? "No readers found. Make sure the reader is powered on."
                }
                return
            }
            if isDiscovering {
                pollBridgeState()
            }
        }
    }
    
    func createLocation() {
        isCreatingLocation = true
        locationResult = nil
        let name = locationDisplayName.isEmpty ? shopName : locationDisplayName
        TerminalBridge.shared.createLocation(
            shopId: shopId,
            displayName: name,
            addressLine1: addressLine1,
            city: addressCity,
            state: addressState,
            postalCode: addressPostalCode,
            country: "US"
        ) { success, result in
            DispatchQueue.main.async {
                isCreatingLocation = false
                if success {
                    locationId = result
                    locationResult = "Location created: \(result ?? "")"
                    if let locId = result, !shopId.isEmpty {
                        saveLocationIdToFirestore(shopId: shopId, locationId: locId)
                    }
                } else {
                    locationResult = "Error: \(result ?? "Unknown error")"
                }
            }
        }
    }
    
    private func checkDisconnectStatus() {
        if !TerminalBridge.shared.isConnected {
            isDisconnecting = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkDisconnectStatus()
            }
        }
    }
    
    func registerReader() {
        isRegistering = true
        registrationResult = nil
        let label = readerLabel.isEmpty ? "Kiosk Reader" : readerLabel
        TerminalBridge.shared.registerReader(
            shopId: shopId,
            registrationCode: registrationCode,
            label: label
        ) { success, result in
            DispatchQueue.main.async {
                isRegistering = false
                if success {
                    registrationResult = result ?? "Reader registered successfully"
                    registrationCode = ""
                    readerLabel = ""
                } else {
                    registrationResult = "Error: \(result ?? "Unknown error")"
                }
            }
        }
    }
    
    private func saveLocationIdToFirestore(shopId: String, locationId: String) {
        Task {
            try? await Firestore.firestore().collection("shops").document(shopId).updateData([
                "terminalLocationId": locationId
            ])
        }
    }
    
}
#endif
