import SwiftUI

/// A drop-in replacement for `.font(.system(size:weight:design:))` that scales the
/// given point size with the user's Dynamic Type setting.
///
/// The app's design uses fixed `.system(size:)` fonts, which do not respond to the
/// accessibility text-size slider — a significant accessibility gap. This modifier
/// keeps the exact same rendered size at the default content-size category (so the
/// default look is unchanged) while scaling proportionally at larger sizes.
///
/// Usage: `.scaledFont(15, weight: .semibold)` in place of
/// `.font(.system(size: 15, weight: .semibold))`.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Apply a Dynamic-Type-aware system font at the given base point size.
    func scaledFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}
