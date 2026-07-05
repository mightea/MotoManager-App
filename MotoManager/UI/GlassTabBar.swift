import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case fuel
    case workshop
    case service
    case parts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fuel: return "Tanken"
        case .workshop: return "Werkstatt"
        case .service: return "Service"
        case .parts: return "Teile"
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .workshop: return "wrench.adjustable.fill"
        case .service: return "exclamationmark.triangle.fill"
        case .parts: return "shippingbox.fill"
        }
    }
}

/// Floating glass pill at the bottom of the screen with the app tabs.
/// Active tab is rendered as a solid primary-coloured inner pill with its
/// label; inactive tabs show icon-only so four tabs fit on narrow devices.
struct GlassTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(6)
        .frame(height: 62)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
        .padding(.horizontal, Theme.Spacing.m)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let active = selection == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                if active {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(active ? Theme.Colors.primary : Color.clear)
                    .shadow(
                        color: active ? Theme.Colors.primary.opacity(0.5) : .clear,
                        radius: 12, x: 0, y: 4
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
