import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var identifier = ""
    @State private var password = ""
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Immersive background
            LiquidBackgroundView().ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                
                // Branded Header
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Theme.Colors.primary)
                        .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 20)
                        .rotationEffect(.degrees(isAnimating ? 5 : -5))
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                    
                    VStack(spacing: 4) {
                        Text("MotoManager")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                        Text("PREMIUM FLEET MANAGEMENT")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(3)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
                
                // Glass-morphic Login Card
                VStack(spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Label("Identifier", systemImage: "person.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        TextField("Username or Email", text: $identifier)
                            .textFieldStyle(ModernTextFieldStyle())
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Label("Password", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(ModernTextFieldStyle())
                            .textContentType(.password)
                    }
                    
                    if let error = authVM.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .foregroundColor(.red)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Button(action: {
                        Task {
                            await authVM.login(identifier: identifier, password: password)
                        }
                    }) {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("SIGN IN")
                        }
                    }
                    .buttonStyle(ModernButtonStyle(isLoading: authVM.isLoading))
                    .disabled(authVM.isLoading || identifier.isEmpty || password.isEmpty)
                    
                    // Passkey Option
                    Button(action: {
                        Task {
                            await authVM.loginWithPasskey(username: identifier.isEmpty ? nil : identifier)
                        }
                    }) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                            Text("Sign in with Passkey")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(Theme.Radius.m)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .foregroundColor(.white)
                    .disabled(authVM.isLoading)
                }
                .padding(Theme.Spacing.l)
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.Radius.l)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
                
                Spacer()
                
                // Footer
                VStack(spacing: 8) {
                    Text("Secure Cloud Sync Enabled")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    HStack(spacing: 20) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("System Operational")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, Theme.Spacing.m)
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView().environmentObject(AuthViewModel())
    }
}
