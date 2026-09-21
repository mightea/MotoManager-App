import SwiftUI

/// iOS-style pill segmented control matching the Claude Design prototype.
/// Each segment renders a label and (optionally) a trailing count badge.
///
/// This is the app's single segmented-control idiom — used on the home tabs
/// *and* inside sheets, so tab chrome and form chrome share one visual
/// language (previously sheets used a separately-styled native `Picker`).
///
/// The active segment is a raised Liquid Glass pill that **morphs** between
/// segments: the indicator and the surrounding track live in the same
/// `GlassEffectContainer`, and the indicator carries a shared `.glassEffectID`
/// so it flows to the newly-selected segment under the selection animation.
struct GlassSegmentedControl<Value: Hashable>: View {
    let segments: [Segment]
    @Binding var selection: Value
    @Namespace private var glassNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Segment: Identifiable {
        var id: Value { value }
        let value: Value
        let label: String
        var count: Int? = nil
    }

    var body: some View {
        GlassEffectContainer(spacing: 3) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(segments) { segment in
                    segmentButton(segment)
                }
            }
            .padding(3)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        // Animation is scoped to this subtree instead of wrapping the
        // selection change in `withAnimation`: a global transaction would
        // animate *everything* driven by the selection — the header's stat
        // pills and the page content visibly wobbled on every tab switch.
        // Only the indicator morph should animate.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
        // Subtle selection tick on segment change (HIG: feedback for
        // user-initiated state changes) — every control instance app-wide
        // inherits it from here.
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isActive = selection == segment.value
        return Button {
            selection = segment.value
        } label: {
            HStack(spacing: 6) {
                Text(segment.label)
                    .scaledFont(13, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                if let count = segment.count {
                    Text("\(count)")
                        .scaledFont(11, weight: .heavy)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isActive
                                    ? AnyShapeStyle(Theme.Colors.primary)
                                    : AnyShapeStyle(Color.primary.opacity(0.10))
                            )
                        )
                }
            }
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .background {
                // Only the active segment renders the glass indicator; the shared
                // glassEffectID lets it morph to whichever segment becomes active.
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                        .fill(Color.clear)
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.controlInner)
                        )
                        .glassEffectID("selection", in: glassNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.label)
        .accessibilityValue(segment.count.map { "\($0) Einträge" } ?? "")
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
