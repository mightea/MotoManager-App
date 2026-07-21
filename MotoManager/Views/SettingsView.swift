import SwiftUI

/// Sectioned-card settings sheet. Only functional entries: the dev-only
/// backend switcher (compiled into Debug builds exclusively, so TestFlight
/// and App Store builds can never leave the production API), the logout
/// button, and a version footer fed from the bundle's marketing version and
/// build number.
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    #if DEBUG
    @State private var selectedBaseURL = NetworkManager.shared.baseURL

    private let environments: [(String, String)] = [
        ("Production", "https://moto-api.herrmann.ltd"),
        ("Development", "http://localhost:3001")
    ]
    #endif

    /// "v0.2.0 (302)" — CI stamps MARKETING_VERSION and the build number
    /// into the archive; local builds show the project defaults.
    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "MotoManager · v\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if DEBUG
                section(title: "ENTWICKLUNG") { envPicker }
                #endif

                logoutButton
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                Text(versionString)
                    .scaledFont(10, weight: .medium)
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .background(sheetBackground)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Einstellungen")
                .scaledFont(17, weight: .bold)
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(12, weight: .bold)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schliessen")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .glassEffect(.regular, in: Rectangle())
    }

    // MARK: - Development section (Debug builds only)

    #if DEBUG
    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .scaledFont(10, weight: .heavy)
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
                .padding(.horizontal, 26)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(Theme.Glass.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
        }
    }

    private var envPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                settingIcon("server.rack")

                Text("Backend")
                    .scaledFont(14, weight: .medium)
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Picker("Backend", selection: $selectedBaseURL) {
                    ForEach(environments, id: \.1) { name, url in
                        Text(name).tag(url)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Glass.mutedText)
                .onChange(of: selectedBaseURL) { _, newValue in
                    NetworkManager.shared.baseURL = newValue
                    authVM.resetSession()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.leading, 56)

            HStack(spacing: 12) {
                settingIcon("network")
                Text("Endpoint")
                    .scaledFont(14, weight: .medium)
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text(selectedBaseURL)
                    .scaledFont(11, design: .monospaced)
                    .foregroundColor(Theme.Glass.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private func settingIcon(_ systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10))
            Image(systemName: systemImage)
                .scaledFont(13, weight: .semibold)
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(width: 30, height: 30)
    }
    #endif

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            authVM.logout()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .scaledFont(14, weight: .semibold)
                Text("Abmelden")
                    .scaledFont(14, weight: .semibold)
            }
            .foregroundColor(Theme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.accent.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [
                Theme.Colors.navy900.opacity(0.6),
                Theme.Colors.navy950.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AuthViewModel())
    }
}
