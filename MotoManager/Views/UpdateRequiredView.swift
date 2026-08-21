import SwiftUI

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

                Text("Diese App-Version wird nicht mehr unterstützt und kann sich nicht mehr mit dem Server verbinden. Bitte installiere die neueste Version über TestFlight bzw. den App Store.")
                    .scaledFont(15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.l)

                Spacer()

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
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.primary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }
}

/// Transient reminder shown after login when the build is at or below the
/// soft upgrade requirement. Auto-dismisses; tapping dismisses immediately.
struct AppUpdateToast: View {
    @ObservedObject private var upgradeManager = AppUpgradeManager.shared

    var body: some View {
        if upgradeManager.showUpdateToast {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(Theme.Colors.primary)
                Text("Eine neue App-Version ist verfügbar – bitte aktualisiere die App.")
                    .scaledFont(13, weight: .semibold)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.glassBorder))
            .padding(.horizontal, Theme.Spacing.l)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    upgradeManager.showUpdateToast = false
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.spring(duration: 0.3)) {
                    upgradeManager.showUpdateToast = false
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Tippen zum Schließen")
        }
    }
}
