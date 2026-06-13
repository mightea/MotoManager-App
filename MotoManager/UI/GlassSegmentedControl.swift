import SwiftUI

/// iOS-style pill segmented control matching the Claude Design prototype.
/// Each segment renders a label and (optionally) a trailing count badge.
/// The active segment fills with a raised surface and a colored count pill.
///
/// Mirrors the visual treatment from
/// `ServiceScreen.jsx` lines 16–44 and `WorkshopScreen.jsx` lines 35–57.
struct GlassSegmentedControl<Value: Hashable>: View {
    let segments: [Segment]
    @Binding var selection: Value

    struct Segment: Identifiable {
        let id = UUID()
        let value: Value
        let label: String
        var count: Int? = nil
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Glass.segmentRadius)
                .fill(Color.white.opacity(0.10))
        )
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isActive = selection == segment.value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selection = segment.value
            }
        } label: {
            HStack(spacing: 6) {
                Text(segment.label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let count = segment.count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundColor(isActive ? .white : .white.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isActive
                                    ? Theme.Colors.primary
                                    : Color.white.opacity(0.10)
                            )
                        )
                }
            }
            .foregroundColor(isActive ? .white : Theme.Glass.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.segmentInnerRadius)
                    .fill(isActive ? Color(white: 0.20) : Color.clear)
                    .shadow(
                        color: isActive ? Color.black.opacity(0.18) : .clear,
                        radius: 3, x: 0, y: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview {
    struct Demo: View {
        @State var tab: String = "a"
        var body: some View {
            ZStack {
                LiquidBackgroundView().ignoresSafeArea()
                GlassSegmentedControl(
                    segments: [
                        .init(value: "a", label: "Mängel", count: 2),
                        .init(value: "b", label: "Wartung", count: 5)
                    ],
                    selection: $tab
                )
                .padding()
            }
        }
    }
    return Demo()
}
