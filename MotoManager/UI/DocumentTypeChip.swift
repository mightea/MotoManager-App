import SwiftUI

/// The document type as a small upper-case tag (e.g. SCHALTPLAN), in the
/// app's eyebrow style: heavy, tracked caps on a quiet capsule. Draws nothing
/// when the document has no (known) type.
struct DocumentTypeChip: View {
    let type: DocumentType?
    /// Base point size; scales with Dynamic Type.
    var size: CGFloat = 9

    var body: some View {
        if let type {
            Text(type.label.uppercased())
                .scaledFont(size, weight: .heavy, design: .monospaced, relativeTo: .caption2)
                .tracking(0.8)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .overlay(Capsule().stroke(Theme.Glass.border, lineWidth: 0.5))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Typ: \(type.label)")
        }
    }
}
