import SwiftUI

/// Hero-photo login screen matching the prototype
/// (`motomanager-app/project/assets/screens/LoginScreen.jsx`).
///
/// - Full-bleed BMW R 80 G/S Wikimedia photo as background with a darken
///   gradient and soft brand halos.
/// - Motorsport stripe at top.
/// - MM wheel brand mark + wordmark + eyebrow.
/// - "Willkommen zurück." headline + sub-line.
/// - Glass form card with username + password (show/hide), primary "Anmelden"
///   button, "Oder" divider, and secondary "Mit Passkey anmelden" button.
struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field { case identifier, password }

    /// BMW R 80 G/S photo on Wikimedia Commons (CC BY-SA 3.0, Gastair).
    private let heroImageURL = URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/28/BMW_R80GS_GENUINE_7.JPG/1280px-BMW_R80GS_GENUINE_7.JPG")!

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !authVM.isLoading
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    brandBlock
                    form
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            ZStack {
                heroBackground
                darkenOverlay
                brandHalos
                stripe
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background layers

    private var heroBackground: some View {
        AsyncImage(url: heroImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Theme.Colors.navy900
            }
        }
        .scaleEffect(1.05)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
    }

    private var darkenOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.Colors.navy950.opacity(0.55), location: 0.0),
                .init(color: Theme.Colors.navy950.opacity(0.85), location: 0.55),
                .init(color: Theme.Colors.navy950.opacity(0.97), location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var brandHalos: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.primary.opacity(0.25))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -120, y: -240)
            Circle()
                .fill(Theme.Colors.accent.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 140, y: 200)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var stripe: some View {
        VStack(spacing: 0) {
            MotorsportStripe()
                .padding(.top, 50)
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Brand block

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                wheelMark
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEINE DIGITALE GARAGE")
                        .scaledFont(9, weight: .heavy)
                        .tracking(1.8)
                        .foregroundColor(.white.opacity(0.55))
                    Text("MotoManager")
                        .scaledFont(17, weight: .black)
                        .foregroundColor(.white)
                }
            }
            Text("Willkommen\nzurück.")
                .scaledFont(30, weight: .heavy)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 1)
            Text("Melde dich an, um deine Garage zu öffnen.")
                .scaledFont(13, weight: .medium)
                .foregroundColor(.white.opacity(0.65))
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var wheelMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

            // Wheel + spokes mark — mirrors the SVG in BrandMark
            Image(systemName: "circle.dotted.circle")
                .scaledFont(19, weight: .semibold)
                .foregroundColor(.white)
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 10) {
            inputField(
                label: "BENUTZERNAME",
                icon: "person.fill",
                text: $identifier,
                placeholder: "marc.schneider",
                contentType: .username,
                field: .identifier
            )
            inputField(
                label: "PASSWORT",
                icon: "lock.fill",
                text: $password,
                placeholder: "••••••••",
                contentType: .password,
                field: .password,
                isSecure: !showPassword,
                trailing: AnyView(
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .scaledFont(13, weight: .semibold)
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 30, height: 30)
                    }
                )
            )

            if let error = authVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                }
                .scaledFont(12, weight: .semibold)
                .foregroundColor(Theme.Colors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
                )
            }

            primaryButton
            divider
            passkeyButton
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 36)
    }

    private func inputField(
        label: String,
        icon: String,
        text: Binding<String>,
        placeholder: String,
        contentType: UITextContentType,
        field: Field,
        isSecure: Bool = false,
        trailing: AnyView? = nil
    ) -> some View {
        let focused = focusedField == field
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .scaledFont(10, weight: .semibold)
                    .foregroundColor(focused ? Theme.Colors.primary : .white.opacity(0.5))
                Text(label)
                    .scaledFont(9, weight: .heavy)
                    .tracking(0.6)
                    .foregroundColor(focused ? Theme.Colors.primary : .white.opacity(0.5))
            }
            HStack(spacing: 6) {
                Group {
                    if isSecure {
                        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                    } else {
                        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.3)))
                    }
                }
                .focused($focusedField, equals: field)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(field == .identifier || field == .password)
                .scaledFont(16, weight: .semibold)
                .foregroundColor(.white)
                .submitLabel(field == .identifier ? .next : .go)
                .onSubmit {
                    if field == .identifier {
                        focusedField = .password
                    } else if canSubmit {
                        submit()
                    }
                }

                if let trailing {
                    trailing
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(focused ? Theme.Colors.primary.opacity(0.18) : Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    focused ? Theme.Colors.primary.opacity(0.45) : Color.white.opacity(0.06),
                    lineWidth: focused ? 1 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private var primaryButton: some View {
        Button(action: submit) {
            ZStack {
                if authVM.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Anmelden")
                }
            }
            .scaledFont(15, weight: .heavy)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .glassActionButton(.primary, in: .roundedRectangle(radius: 14))
        .disabled(!canSubmit)
        .animation(.easeOut(duration: 0.18), value: canSubmit)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
            Text("ODER")
                .scaledFont(11, weight: .heavy)
                .tracking(0.6)
                .foregroundColor(Theme.Glass.mutedText)
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
        .padding(.vertical, 2)
    }

    private var passkeyButton: some View {
        Button {
            Task {
                await authVM.loginWithPasskey(username: identifier.isEmpty ? nil : identifier)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                    .scaledFont(16, weight: .semibold)
                Text("Mit Passkey anmelden")
                    .scaledFont(15, weight: .bold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .glassActionButton(.secondary, in: .roundedRectangle(radius: 14))
        .disabled(authVM.isLoading)
    }

    private func submit() {
        Task {
            await authVM.login(identifier: identifier, password: password)
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView().environmentObject(AuthViewModel())
    }
}
