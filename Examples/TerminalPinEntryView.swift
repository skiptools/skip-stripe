import SkipFuseUI
#if os(Android)
import SkipFirebaseFirestore
import SkipFirebaseAuth
#else
import FirebaseFirestore
@preconcurrency import FirebaseAuth
#endif

struct TerminalPinEntryView: View {
    let isSettingNewPin: Bool
    let shopId: String
    let existingPin: String
    let onSuccess: (String?) -> Void
    let onCancel: () -> Void
    var onChangeLocation: (() -> Void)? = nil
    
    @State var pinInput = ""
    @State var pinConfirmInput = ""
    @State var pinError: String? = nil
    @State var showPin = false
    @State var showConfirmPin = false
    @State var isResettingPin = false
    @State var resetEmail = ""
    @State var resetPassword = ""
    @State var showResetPassword = false
    @State var isAuthenticating = false
    @State var resetAuthenticated = false
    
    private var currentMode: String {
        if isResettingPin && !resetAuthenticated { return "auth" }
        if isResettingPin && resetAuthenticated { return "newPin" }
        if isSettingNewPin { return "newPin" }
        return "unlock"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: currentMode == "auth" ? "key.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                Text(currentMode == "auth" ? "Owner Sign In" : (currentMode == "newPin" ? "Set New PIN" : "Enter Security PIN"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(currentMode == "auth" ? "Sign in with the owner account to reset the PIN." : (currentMode == "newPin" ? "Create a new PIN to protect Terminal Setup access." : "Enter your PIN to access Terminal Setup."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if currentMode == "auth" {
                    ownerAuthFields
                } else {
                    pinFields
                }
                
                if let error = pinError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if currentMode == "auth" {
                    authButton
                } else {
                    submitButton
                }
                
                if currentMode == "unlock" {
                    VStack(spacing: 8) {
                        if let changeLocation = onChangeLocation {
                            Button(action: { changeLocation() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text("Change Location")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            isResettingPin = true
                            pinError = nil
                            resetEmail = ""
                            resetPassword = ""
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                Text("Forgot PIN? Reset")
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.top, 4)
                }
                
                if currentMode == "auth" {
                    Button(action: {
                        isResettingPin = false
                        resetAuthenticated = false
                        pinError = nil
                    }) {
                        Text("Back to PIN Entry")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .navigationTitle(currentMode == "auth" ? "Reset PIN" : (currentMode == "newPin" ? "Set PIN" : "Security PIN"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear {
                pinInput = ""
                pinConfirmInput = ""
                pinError = nil
                showPin = false
                showConfirmPin = false
                isResettingPin = false
                resetAuthenticated = false
            }
        }
    }
    
    private var pinFields: some View {
        VStack(spacing: 12) {
            HStack {
                if showPin {
                    TextField("PIN", text: $pinInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                } else {
                    SecureField("PIN", text: $pinInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                
                Button(action: { showPin.toggle() }) {
                    Image(systemName: showPin ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: 250)
            
            if isSettingNewPin || resetAuthenticated {
                HStack {
                    if showConfirmPin {
                        TextField("Confirm PIN", text: $pinConfirmInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    } else {
                        SecureField("Confirm PIN", text: $pinConfirmInput)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                    
                    Button(action: { showConfirmPin.toggle() }) {
                        Image(systemName: showConfirmPin ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.gray)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(maxWidth: 250)
            }
        }
    }
    
    private var ownerAuthFields: some View {
        VStack(spacing: 12) {
            TextField("Owner Email", text: $resetEmail)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .frame(maxWidth: 300)
            
            HStack {
                if showResetPassword {
                    TextField("Password", text: $resetPassword)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Password", text: $resetPassword)
                        .textFieldStyle(.roundedBorder)
                }
                
                Button(action: { showResetPassword.toggle() }) {
                    Image(systemName: showResetPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: 300)
        }
    }
    
    private var authButton: some View {
        Button(action: authenticateOwner) {
            HStack {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(isAuthenticating ? "Signing In..." : "Sign In & Reset PIN")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(resetEmail.isEmpty || resetPassword.isEmpty ? Color.gray : Color.blue)
            .cornerRadius(12)
        }
        .disabled(resetEmail.isEmpty || resetPassword.isEmpty || isAuthenticating)
        .padding(.horizontal)
    }
    
    private var submitButton: some View {
        Button(action: handleSubmit) {
            Text(isSettingNewPin || resetAuthenticated ? "Set PIN & Continue" : "Unlock")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
        .disabled(pinInput.isEmpty)
        .padding(.horizontal)
    }
    
    private func authenticateOwner() {
        isAuthenticating = true
        pinError = nil
        
        Task {
            do {
                let _ = try await Auth.auth().signIn(withEmail: resetEmail, password: resetPassword)
                await MainActor.run {
                    isAuthenticating = false
                    resetAuthenticated = true
                    pinInput = ""
                    pinConfirmInput = ""
                    pinError = nil
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    pinError = "Authentication failed. Make sure you're using the owner account."
                }
            }
        }
    }
    
    private func handleSubmit() {
        if isSettingNewPin || resetAuthenticated {
            guard pinInput.count >= 4 else {
                pinError = "PIN must be at least 4 digits."
                return
            }
            guard pinInput == pinConfirmInput else {
                pinError = "PINs do not match."
                return
            }
            if !shopId.isEmpty {
                let pin = pinInput
                let sid = shopId
                Task {
                    try? await Firestore.firestore().collection("shops").document(sid).updateData([
                        "terminalPin": pin
                    ])
                }
            }
            onSuccess(pinInput)
        } else {
            guard pinInput == existingPin else {
                pinError = "Incorrect PIN."
                pinInput = ""
                return
            }
            onSuccess(nil)
        }
    }
}
