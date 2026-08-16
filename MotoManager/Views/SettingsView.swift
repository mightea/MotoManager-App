import SwiftUI

/// Sectioned-card settings sheet. Only functional entries: the logout
/// button and a version footer fed from the bundle's marketing version and
/// build number. The server URL is chosen on the login screen, not here.
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

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
                logoutButton
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        // Pinned to the bottom of the sheet, independent of scroll content.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(versionString)
                .scaledFont(10, weight: .medium)
                .foregroundColor(.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
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
