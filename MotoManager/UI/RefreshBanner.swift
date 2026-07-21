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
                    .scaledFont(13, weight: .semibold)
                Text("Aktualisierung fehlgeschlagen – gespeicherte Daten werden angezeigt.")
                    .scaledFont(12, weight: .semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        viewModel.refreshFailed = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(12, weight: .bold)
                        // Comfortable tap target for the small glyph.
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hinweis schließen")
            }
            .foregroundColor(.white)
            .padding(.leading, 14)
            .padding(.trailing, 6)
            // Fill the width up to the add button and match its 60pt height so
            // the two-line message always fits.
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .glassEffect(.regular, in: Capsule())
            .overlay(Capsule().stroke(Theme.Colors.accent.opacity(0.5), lineWidth: 0.5))
            // Outer positioning is owned by `bottomActionBar`.
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
