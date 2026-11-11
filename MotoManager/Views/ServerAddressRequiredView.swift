import SwiftUI

/// Shown instead of the app when the user is signed in but the server
/// address is unknown and could not be recovered from the local caches
/// (see `AuthViewModel.restoreServerAddressIfMissing()`). Entering the
/// address keeps the session and everything still waiting to sync; the
/// address is only adopted once the server accepts the stored login.
struct ServerAddressRequiredView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var address = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var confirmingLogout = false
    @FocusState private var addressFocused: Bool

    private var canConnect: Bool {
        ServerAddress.normalize(address) != nil && !isConnecting
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                Spacer()

                Image(systemName: "server.rack")
                    .scaledFont(56, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)

                Text("Serveradresse fehlt")
                    .scaledFont(24, weight: .black)

                Text("Du bist angemeldet, aber die Adresse deines Servers ist nach dem Update nicht mehr gespeichert. Gib sie erneut ein – deine Daten und noch nicht synchronisierte Änderungen bleiben erhalten.")
                    .scaledFont(15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.l)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    TextField("https://moto.example.com", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($addressFocused)
                        .onSubmit(connect)
                        .disabled(isConnecting)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Serveradresse")
                        .accessibilityIdentifier("serverAddress.field")

                    if let errorMessage {
                        Text(errorMessage)
                            .scaledFont(13)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("serverAddress.error")
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)

                Spacer()

                VStack(spacing: Theme.Spacing.s) {
                    Button(action: connect) {
                        HStack(spacing: 8) {
                            if isConnecting {
                                ProgressView().controlSize(.small)
                            }
                            Text("Verbinden")
                                .scaledFont(15, weight: .semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.primary)
                    .disabled(!canConnect)
                    .accessibilityIdentifier("serverAddress.connect")

                    Button(role: .destructive) {
                        confirmingLogout = true
                    } label: {
                        Text("Abmelden")
                            .scaledFont(15, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isConnecting)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .frame(maxWidth: AdaptiveLayout.formMaxWidth)
        }
        .onChange(of: address) { errorMessage = nil }
        .confirmationDialog("Abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { authVM.logout() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Noch nicht synchronisierte Änderungen gehen dabei verloren.")
        }
    }

    private func connect() {
        guard canConnect else { return }
        addressFocused = false
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                try await authVM.reconnect(to: address)
            } catch {
                errorMessage = Self.message(for: error)
            }
            isConnecting = false
        }
    }

    /// A rejected token here means "wrong server", not "wrong password".
    static func message(for error: Error) -> String {
        if case APIError.unauthorized = error {
            return "Dieser Server kennt deine Anmeldung nicht. Prüfe die Adresse – oder melde dich ab und neu an."
        }
        return LoginErrorMessage.text(for: error, method: .password)
            ?? "Verbindung fehlgeschlagen. Prüfe die Adresse."
    }
}
