import SwiftUI

/// Hero-photo login screen matching the prototype
/// (`motomanager-app/project/assets/screens/LoginScreen.jsx`).
///
/// - Full-bleed bundled BMW R 80 G/S photo as background with a darken gradient
///   and soft brand halos.
/// - Motorsport stripe at top.
/// - MM wheel brand mark + wordmark + eyebrow.
/// - "Willkommen zurück." headline + sub-line.
/// - Glass form card with server URL, username + password (show/hide),
///   primary "Anmelden" button, "Oder" divider, and secondary
///   "Mit Passkey anmelden" button.
struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var serverURL: String = NetworkManager.shared.baseURL
    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    /// Height of the screen area without the keyboard, and of the brand block
    /// plus form. Used to centre the column once, so the keyboard appearing or
    /// closing never moves it.
    @State private var fullHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    /// The shown error belongs to the previous attempt; the user has edited
    /// the form since. Shown dimmed instead of removed (no layout change).
    @State private var errorIsStale = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case server, identifier, password

        var accessibilityIdentifier: String {
            switch self {
            case .server: "login.server"
            case .identifier: "login.identifier"
            case .password: "login.password"
            }
        }
    }

    /// The entered server URL, trimmed and without trailing slashes — or nil
    /// when it isn't a usable http(s) URL. Requests append `/api/...` paths,
    /// so the stored base must not end in a slash.
    private var normalizedServerURL: String? {
        var trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return trimmed
    }

    private var canSubmit: Bool {
        normalizedServerURL != nil
            && !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !authVM.isBusy
    }

    /// Centres the column in the keyboard-free screen height. Because neither
    /// height changes with the keyboard or with status messages, the column
    /// stays put while logging in.
    private var topInset: CGFloat {
        max(40, (fullHeight - contentHeight) / 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                brandBlock
                form
            }
            // Readable form column on iPad — the hero photo stays
            // full-bleed, only brand block + form are capped.
            .frame(maxWidth: AdaptiveLayout.formMaxWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .padding(.top, topInset)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        // Hidden until measured, so the first frame doesn't jump into place.
        .opacity(fullHeight == 0 ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
        }
        .background(alignment: .top) {
            ZStack {
                heroBackground
                darkenOverlay
                brandHalos
                stripe
            }
        }
        .preferredColorScheme(.dark)
        // Connect link from the webapp: take over server and username, then
        // only the password is left to type.
        .onReceive(ConnectLinkRouter.shared.$pending) { link in
            guard let link else { return }
            ConnectLinkRouter.shared.pending = nil
            serverURL = link.server
            if let user = link.username { identifier = user }
            focusedField = link.username == nil ? .identifier : .password
            AccessibilityNotification.Announcement("Server und Benutzername übernommen").post()
        }
    }

    // MARK: - Background layers

    private var heroBackground: some View {
        Image("LoginHero")
            .resizable()
            .scaledToFill()
            .accessibilityHidden(true)
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
        // Proportional placement + size so the halos frame the content on any
        // canvas instead of clustering at phone-tuned pixel offsets.
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let size = max(280, min(w, h) * 0.5)
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.25))
                    .frame(width: size, height: size)
                    .blur(radius: 80)
                    .position(x: w * 0.2, y: h * 0.22)
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.18))
                    .frame(width: size, height: size)
                    .blur(radius: 80)
                    .position(x: w * 0.85, y: h * 0.72)
            }
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
                        .foregroundStyle(.white.opacity(0.55))
                    Text("MotoManager")
                        .scaledFont(17, weight: .black)
                        .foregroundStyle(.white)
                }
            }
            Text("Willkommen\nzurück.")
                .scaledFont(30, weight: .heavy)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 1)
            Text("Melde dich an, um deine Garage zu öffnen.")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(.white.opacity(0.65))
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
                .foregroundStyle(.white)
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 10) {
            inputField(
                label: "SERVER",
                icon: "server.rack",
                text: $serverURL,
                placeholder: "https://moto.example.com",
                contentType: .URL,
                field: .server,
                keyboard: .URL
            )
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
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 30, height: 30)
                    }
                )
            )

            statusLine

            primaryButton
            divider
            passkeyButton
        }
        .padding(16)
        .onChange(of: identifier) { errorIsStale = true }
        .onChange(of: password) { errorIsStale = true }
        .onChange(of: serverURL) { errorIsStale = true }
        .onChange(of: authVM.errorMessage) { _, message in
            errorIsStale = false
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: authVM.phase) { _, phase in
            if let status = phase.statusText {
                AccessibilityNotification.Announcement(status).post()
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 36)
    }

    // MARK: - Status line

    /// One fixed-height line under the fields for login progress and errors.
    /// Its height is reserved even when empty, so a message appearing,
    /// changing or going away never resizes the card.
    private var statusLine: some View {
        ZStack(alignment: .leading) {
            // Reserves two lines at the current text size.
            Text("X\nX")
                .scaledFont(12, weight: .semibold)
                .padding(.vertical, 8)
                .hidden()
                .accessibilityHidden(true)

            if let status = authVM.phase.statusText {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(status)
                        .contentTransition(.opacity)
                }
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 12)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            } else if let error = authVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Colors.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
                )
                .opacity(errorIsStale ? 0.5 : 1)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("login.error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: authVM.phase)
        .animation(.easeOut(duration: 0.2), value: authVM.errorMessage)
        .animation(.easeOut(duration: 0.2), value: errorIsStale)
        .accessibilityIdentifier("login.status")
    }

    private func inputField(
        label: String,
        icon: String,
        text: Binding<String>,
        placeholder: String,
        contentType: UITextContentType,
        field: Field,
        keyboard: UIKeyboardType = .default,
        isSecure: Bool = false,
        trailing: AnyView? = nil
    ) -> some View {
        let focused = focusedField == field
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .scaledFont(10, weight: .semibold)
                    .foregroundStyle(focused ? Theme.Colors.primary : .white.opacity(0.5))
                Text(label)
                    .scaledFont(9, weight: .heavy)
                    .tracking(0.6)
                    .foregroundStyle(focused ? Theme.Colors.primary : .white.opacity(0.5))
            }
            HStack(spacing: 6) {
                Group {
                    if isSecure {
                        SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                    } else {
                        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                    }
                }
                .focused($focusedField, equals: field)
                .disabled(authVM.isBusy)
                .accessibilityIdentifier(field.accessibilityIdentifier)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(.white)
                .submitLabel(field == .password ? .go : .next)
                .onSubmit {
                    switch field {
                    case .server:
                        focusedField = .identifier
                    case .identifier:
                        focusedField = .password
                    case .password:
                        if canSubmit { submit() }
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
        let spinning = authVM.activeMethod == .password
        return Button(action: submit) {
            // The label stays in the layout (just hidden) so the button keeps
            // its size while the spinner shows.
            ZStack {
                Text("Anmelden")
                    .opacity(spinning ? 0 : 1)
                if spinning {
                    ProgressView().tint(.white)
                }
            }
            .scaledFont(15, weight: .heavy)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
        }
        .glassActionButton(.primary, in: .roundedRectangle(radius: 14))
        // The running button stays fully opaque; taps are ignored in submit().
        .disabled(authVM.isBusy ? !spinning : !canSubmit)
        .accessibilityLabel(spinning ? (authVM.phase.statusText ?? "Anmelden") : "Anmelden")
        .accessibilityIdentifier("login.submit")
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
                .foregroundStyle(Theme.Glass.mutedText)
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
        .padding(.vertical, 2)
    }

    private var passkeyButton: some View {
        let spinning = authVM.activeMethod == .passkey
        return Button {
            guard !authVM.isBusy, normalizedServerURL != nil else { return }
            focusedField = nil
            applyServerURL()
            Task {
                let username = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                await authVM.loginWithPasskey(username: username.isEmpty ? nil : username)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                    .scaledFont(16, weight: .semibold)
                Text("Mit Passkey anmelden")
                    .scaledFont(15, weight: .bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(spinning ? 0 : 1)
            .overlay {
                if spinning {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.vertical, 6)
        }
        .glassActionButton(.secondary, in: .roundedRectangle(radius: 14))
        .disabled(authVM.isBusy ? !spinning : normalizedServerURL == nil)
        .accessibilityLabel(spinning ? (authVM.phase.statusText ?? "Mit Passkey anmelden") : "Mit Passkey anmelden")
        .accessibilityIdentifier("login.passkey")
    }

    /// Persists the entered server URL so the login request (and every call
    /// after it) targets the chosen backend.
    private func applyServerURL() {
        guard let base = normalizedServerURL, base != NetworkManager.shared.baseURL else { return }
        NetworkManager.shared.baseURL = base
    }

    private func submit() {
        guard canSubmit else { return }
        // Close the keyboard before the request starts, not at some random
        // point while the login is running.
        focusedField = nil
        applyServerURL()
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
