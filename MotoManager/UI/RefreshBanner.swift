import SwiftUI

/// Non-blocking toast shown when a refresh fails but cached data is still on
/// screen. Renders nothing (zero size) when there's nothing to report, so it can
/// sit in a layout unconditionally. Successful refreshes clear `refreshFailed`.
struct RefreshBanner: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    var body: some View {
        if viewModel.refreshFailed {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                Text("Aktualisierung fehlgeschlagen – gespeicherte Daten werden angezeigt.")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        viewModel.refreshFailed = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .accessibilityLabel("Hinweis schließen")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.Colors.accent.opacity(0.5), lineWidth: 0.5))
            .padding(.horizontal, Theme.Spacing.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
