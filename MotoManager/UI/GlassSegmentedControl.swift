import SwiftUI

/// iOS-style pill segmented control matching the Claude Design prototype.
/// Each segment renders a label and (optionally) a trailing count badge.
///
/// The active segment is a raised Liquid Glass pill that **morphs** between
/// segments: the indicator and the surrounding track live in the same
/// `GlassEffectContainer`, and the indicator carries a shared `.glassEffectID`
/// so it flows to the newly-selected segment under the selection animation
/// (replacing the former solid `Color(white:)` fill + fake shadow).
///
/// Mirrors the visual treatment from
/// `ServiceScreen.jsx` lines 16–44 and `WorkshopScreen.jsx` lines 35–57.
struct GlassSegmentedControl<Value: Hashable>: View {
    let segments: [Segment]
    @Binding var selection: Value
    @Namespace private var glassNamespace

    struct Segment: Identifiable {
        let id = UUID()
        let value: Value
        let label: String
        var count: Int? = nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    segmentButton(segment)
                }
            }
            .padding(3)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.segmentRadius))
        }
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
                    .scaledFont(13, weight: .semibold)
                    .lineLimit(1)
                if let count = segment.count {
                    Text("\(count)")
                        .scaledFont(11, weight: .heavy)
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
            .background {
                // Only the active segment renders the glass indicator; the shared
                // glassEffectID lets it morph to whichever segment becomes active.
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.Glass.segmentInnerRadius)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: Theme.Glass.segmentInnerRadius)
                        )
                        .glassEffectID("selection", in: glassNamespace)
                }
            }
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
