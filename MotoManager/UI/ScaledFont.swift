import SwiftUI

/// A drop-in replacement for `.font(.system(size:weight:design:))` that scales the
/// given point size with the user's Dynamic Type setting.
///
/// Keeps the exact rendered size at the default content-size category while
/// scaling with the user's preferred content size.
///
/// Usage: `.scaledFont(15, weight: .semibold)` in place of a fixed system font.
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
