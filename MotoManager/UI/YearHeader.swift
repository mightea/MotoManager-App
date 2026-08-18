import SwiftUI

/// hairline — year — hairline divider between year sections of a history list
/// (service Verlauf, fuel list).
struct YearHeader: View {
    let year: String

    init(_ year: String) {
        self.year = year
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.Glass.hairline).frame(height: 0.5)
            Text(year)
                .scaledFont(11, weight: .heavy)
                .monospacedDigit()
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Rectangle().fill(Theme.Glass.hairline).frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }
}
