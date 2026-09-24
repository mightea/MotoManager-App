import Combine
import SwiftUI

/// Scroll-driven state of the persistent motorcycle header. Scrolling the
/// workspace content away from the top shrinks the header to a single row so
/// the records get the space; returning to the top restores the photo header.
@MainActor
final class WorkspaceHeaderState: ObservableObject {
    @Published private(set) var isMinimized = false

    /// Content offset (measured from the top edge, insets excluded) beyond
    /// which the header minimizes.
    static let threshold: CGFloat = 24
    /// Space the header gives back when its height is not measured yet.
    static let estimatedGain: CGFloat = 120

    /// Measured heights, so the decision knows how much room the content will
    /// gain. Without that, a list that barely scrolls would minimize the
    /// header, lose its scroll offset to the taller container, expand again
    /// and flicker.
    private(set) var expandedHeight: CGFloat = 0
    private(set) var minimizedHeight: CGFloat = 0

    var headerGain: CGFloat {
        guard expandedHeight > 0 else { return Self.estimatedGain }
        return max(0, expandedHeight - (minimizedHeight > 0 ? minimizedHeight : expandedHeight * 0.35))
    }

    func recordHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if isMinimized { minimizedHeight = height } else { expandedHeight = height }
    }

    func scrolled(pastThreshold: Bool, maxOffset: CGFloat) {
        let next = Self.shouldMinimize(isMinimized: isMinimized, pastThreshold: pastThreshold,
                                       maxOffset: maxOffset, headerGain: headerGain)
        guard next != isMinimized else { return }
        withAnimation(.snappy(duration: 0.32, extraBounce: 0)) { isMinimized = next }
    }

    /// Pure decision, kept separate for tests. `maxOffset` is how far the
    /// content can scroll in its current container.
    nonisolated static func shouldMinimize(isMinimized: Bool, pastThreshold: Bool,
                                           maxOffset: CGFloat, headerGain: CGFloat) -> Bool {
        guard pastThreshold else { return false }
        if isMinimized { return true }
        // Only minimize when the content still scrolls past the threshold
        // once the container has grown by the header's gain.
        return maxOffset - headerGain > threshold
    }
}

private struct WorkspaceHeaderKey: EnvironmentKey {
    static let defaultValue: WorkspaceHeaderState? = nil
}

extension EnvironmentValues {
    var workspaceHeader: WorkspaceHeaderState? {
        get { self[WorkspaceHeaderKey.self] }
        set { self[WorkspaceHeaderKey.self] = newValue }
    }
}

private struct WorkspaceScrollSample: Equatable {
    let pastThreshold: Bool
    let maxOffset: CGFloat
}

private struct WorkspaceHeaderTracking: ViewModifier {
    let isActive: Bool
    @Environment(\.workspaceHeader) private var header

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: WorkspaceScrollSample.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            let maxOffset = geometry.contentSize.height + geometry.contentInsets.top
                + geometry.contentInsets.bottom - geometry.containerSize.height
            // Coarse values keep the action from firing on every scrolled point.
            return WorkspaceScrollSample(pastThreshold: offset > WorkspaceHeaderState.threshold,
                                         maxOffset: (maxOffset / 8).rounded() * 8)
        } action: { _, sample in
            guard isActive else { return }
            header?.scrolled(pastThreshold: sample.pastThreshold, maxOffset: sample.maxOffset)
        }
    }
}

extension View {
    /// Lets this scroll view (a `List` or `ScrollView`) minimize and restore
    /// the motorcycle header above it. Views that are not beside the header,
    /// e.g. a record pushed full screen on a phone, pass `isActive: false`.
    func tracksWorkspaceHeader(isActive: Bool = true) -> some View {
        modifier(WorkspaceHeaderTracking(isActive: isActive))
    }
}
