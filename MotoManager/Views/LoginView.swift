import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var identifier = ""
    @State private var password = ""
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background
            Theme.Colors.background.ignoresSafeArea()
            
            // Decorative shapes
            Circle()
                .fill(Theme.Colors.primary.opacity(0.1))
                .frame(width: 300, height: 300)
                .offset(x: -150, y: -350)
            
            Circle()
                .fill(Theme.Colors.accent.opacity(0.1))
                .frame(width: 200, height: 200)
                .offset(x: 150, y: 350)
            
            VStack(spacing: Theme.Spacing.l) {
                Spacer()
                
                // Header
                VStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.Colors.primary)
                        .padding(.bottom, Theme.Spacing.s)
                        .rotationEffect(.degrees(isAnimating ? 5 : -5))
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                    
                    Text("MotoManager")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    
                    Text("Manage your fleet with ease")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, Theme.Spacing.xl)
                
                // Form
                VStack(spacing: Theme.Spacing.m) {
                    TextField("Username or Email", text: $identifier)
                        .textFieldStyle(ModernTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(ModernTextFieldStyle())
                }
                
                if let error = authVM.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Button(action: {
                    Task {
                        await authVM.login(identifier: identifier, password: password)
                    }
                }) {
                    if authVM.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(ModernButtonStyle(isLoading: authVM.isLoading))
                .disabled(authVM.isLoading || identifier.isEmpty || password.isEmpty)
                
                Spacer()
                
                Text("V 1.0.0")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(Theme.Spacing.l)
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
