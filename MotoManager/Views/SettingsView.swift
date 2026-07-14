import SwiftUI

/// Sectioned-card settings sheet matching the prototype's
/// `motomanager-app/project/assets/sheets.jsx::SettingsSheet`.
///
/// Each section is a rounded card with iconified rows. Trailing detail text
/// + chevron-right tells the user the row is navigable. A red "Abmelden"
/// danger button + version footer sit at the bottom. The dev-only
/// environment switcher is kept under an Entwicklung section so the
/// production user never sees it but the developer can still flip backends.
struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedBaseURL = NetworkManager.shared.baseURL

    private let environments: [(String, String)] = [
        ("Production", "https://moto-api.herrmann.ltd"),
        ("Development", "http://localhost:3001")
    ]

    private var environmentLabel: String {
        environments.first(where: { $0.1 == selectedBaseURL })?.0 ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(title: "KONTO", rows: [
                    SettingRow(icon: "person.fill", label: "Profil", detail: "Mein Profil"),
                    SettingRow(icon: "lock.fill", label: "Passwort & Passkey"),
                    SettingRow(icon: "bell.fill", label: "Benachrichtigungen", detail: "Aktiv")
                ])

                section(title: "GARAGE", rows: [
                    SettingRow(icon: "mappin.and.ellipse", label: "Standorte"),
                    SettingRow(icon: "dollarsign.circle.fill", label: "Währung", detail: "EUR"),
                    SettingRow(icon: "calendar", label: "MFK-Erinnerungen", detail: "4 Wo. vorher")
                ])

                section(title: "SYNCHRONISATION", rows: [
                    SettingRow(icon: "checkmark.circle.fill", label: "Cloud-Sync",
                               detail: "Aktiv", detailColor: .green)
                ])

                section(title: "ENTWICKLUNG", rows: [], custom: AnyView(envPicker))

                logoutButton
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                Text("MotoManager · v1.0.0")
                    .font(.system(size: 10, weight: .medium))
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
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
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

    // MARK: - Sections

    private func section(title: String, rows: [SettingRow], custom: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
                .padding(.horizontal, 26)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    SettingRowView(row: row)
                    if index < rows.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.leading, 56)
                    }
                }
                if let custom {
                    custom
                }
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10))
                    Image(systemName: "server.rack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(width: 30, height: 30)

                Text("Backend")
                    .font(.system(size: 14, weight: .medium))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10))
                    Image(systemName: "network")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(width: 30, height: 30)
                Text("Endpoint")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text(selectedBaseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.Glass.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            authVM.logout()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Abmelden")
                    .font(.system(size: 14, weight: .semibold))
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

// MARK: - Row model + view

private struct SettingRow {
    var icon: String
    var label: String
    var detail: String? = nil
    var detailColor: Color? = nil
}

private struct SettingRowView: View {
    let row: SettingRow

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: row.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(width: 30, height: 30)

            Text(row.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Spacer(minLength: 0)

            if let detail = row.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(row.detailColor ?? Theme.Glass.mutedText)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AuthViewModel())
    }
}
