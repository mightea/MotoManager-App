import SwiftUI

/// Size-class-driven layout constants for iPad (regular-width) layouts.
enum AdaptiveLayout {
    /// Max width for standalone forms (login).
    static let formMaxWidth: CGFloat = 560
    /// Prevent phone-oriented list rows and separators from stretching across
    /// the entire width of a large iPad or resizable window.
    static let contentMaxWidth: CGFloat = 1_000
}

extension View {
    func adaptiveContentWidth() -> some View {
        frame(maxWidth: AdaptiveLayout.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
