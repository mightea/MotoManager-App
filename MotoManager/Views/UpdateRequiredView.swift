import SwiftUI
import UIKit

/// Where users get a newer build. The app ships through TestFlight only, so
/// this opens MotoManager's page in the TestFlight app; if TestFlight isn't
/// installed, the web page that offers to install it.
enum AppUpdateLink {
    /// App Store Connect → App Information → Apple ID.
    static let appleID = "6789194231"

    static let testFlightApp = URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\(appleID)")!
    static let testFlightWeb = URL(string: "https://beta.itunes.apple.com/v1/app/\(appleID)")!

    @MainActor
    static func open() {
        UIApplication.shared.open(testFlightApp) { opened in
            if !opened {
                UIApplication.shared.open(testFlightWeb)
            }
        }
    }
}

/// Full-screen hard block shown when the backend declared this build out of
/// support: the app makes no further backend requests until it is updated.
/// "Erneut prüfen" re-runs the (exempt) upgrade check so the screen clears
/// on its own once the app was updated or an admin lowered the requirement.
struct UpdateRequiredView: View {
    @ObservedObject private var upgradeManager = AppUpgradeManager.shared
    @State private var isChecking = false

    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                Spacer()

                Image(systemName: "arrow.down.app.fill")
                    .scaledFont(56, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)

                Text("Update erforderlich")
                    .scaledFont(24, weight: .black)

                Text("Diese App-Version wird nicht mehr unterstützt und kann sich nicht mehr mit dem Server verbinden. Bitte installiere die neueste Version über TestFlight.")
                    .scaledFont(15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.l)

                Spacer()

                VStack(spacing: Theme.Spacing.s) {
                    Button {
                        AppUpdateLink.open()
                    } label: {
                        Label("Jetzt aktualisieren", systemImage: "arrow.down.circle.fill")
                            .scaledFont(15, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.primary)

                    Button {
                        guard !isChecking else { return }
                        isChecking = true
                        Task {
                            await upgradeManager.check()
                            isChecking = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isChecking {
                                ProgressView().controlSize(.small)
                            }
                            Text("Erneut prüfen")
                                .scaledFont(15, weight: .semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.primary)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }
}

/// Update prompt shown once per launch (after the post-login check) when the
/// build is at or below the soft upgrade requirement. Stays until the user
/// picks "Jetzt aktualisieren" or "Später".
struct AppUpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()

            Image(systemName: "arrow.down.app.fill")
                .scaledFont(56, weight: .semibold)
                .foregroundStyle(Theme.Colors.primary)

            Text("Neue Version verfügbar")
                .scaledFont(22, weight: .black)

            Text("Für MotoManager gibt es ein Update mit Verbesserungen und Fehlerbehebungen. Installiere die neueste Version über TestFlight.")
                .scaledFont(15)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: Theme.Spacing.s) {
                Button {
                    AppUpdateLink.open()
                    dismiss()
                } label: {
                    Label("Jetzt aktualisieren", systemImage: "arrow.down.circle.fill")
                        .scaledFont(15, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.primary)

                Button {
                    dismiss()
                } label: {
                    Text("Später")
                        .scaledFont(15, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xl)
        .glassSheet()
    }
}
