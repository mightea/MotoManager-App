import SwiftUI

/// Small overlay marking a record that hasn't synced yet. Sits on a row's
/// icon badge; pair with `.accessibilityLabel("Nicht synchronisiert")`.
struct PendingBadge: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 8, weight: .black))
            .foregroundColor(.white)
            .padding(3)
            .background(Circle().fill(Theme.Colors.primary))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
    }
}
