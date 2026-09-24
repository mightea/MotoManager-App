import Combine
import SwiftUI

/// Heights of the motorcycle header in its expanded and minimized shapes.
/// The header measures itself and publishes them here; lists inset their
/// content by the expanded height so records start beneath the photo, and
/// the difference is the distance a list scrolls while the header collapses.
@MainActor
final class WorkspaceHeaderMetrics: ObservableObject {
    /// Estimates until the header has laid out once; exact for default type.
    @Published var expandedHeight: CGFloat = 200
    @Published var minimizedHeight: CGFloat = 60

    /// Points of scroll that take the header from expanded to minimized.
    var gain: CGFloat { max(1, expandedHeight - minimizedHeight) }

    func height(at progress: CGFloat) -> CGFloat {
        expandedHeight - (expandedHeight - minimizedHeight) * progress
    }
}

/// Scroll-linked collapse of the header, 0 (expanded) … 1 (minimized).
/// Updated on every scroll tick, so only the header and the views padded by
/// it observe this object; the lists themselves never re-render from it.
@MainActor
final class WorkspaceScrollProgress: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    func update(offset: CGFloat, gain: CGFloat) {
        let next = Self.progress(offset: offset, gain: gain)
        if next != progress { progress = next }
    }

    /// Pure mapping, kept separate for tests: the header collapses one point
    /// per scrolled point until the whole gain is used, and never stretches
    /// on overscroll so the pull-to-refresh spinner stays visible.
    nonisolated static func progress(offset: CGFloat, gain: CGFloat) -> CGFloat {
        guard gain > 0 else { return offset > 0 ? 1 : 0 }
        return min(max(offset / gain, 0), 1)
    }
}

struct WorkspaceHeaderContext {
    let metrics: WorkspaceHeaderMetrics
    let scroll: WorkspaceScrollProgress
}

private struct WorkspaceHeaderKey: EnvironmentKey {
    static let defaultValue: WorkspaceHeaderContext? = nil
}

extension EnvironmentValues {
    var workspaceHeader: WorkspaceHeaderContext? {
        get { self[WorkspaceHeaderKey.self] }
        set { self[WorkspaceHeaderKey.self] = newValue }
    }
}

// MARK: - Tracking lists

private struct WorkspaceHeaderTracking: ViewModifier {
    @Environment(\.workspaceHeader) private var context

    func body(content: Content) -> some View {
        if let context {
            TrackedScrollContent(metrics: context.metrics, scroll: context.scroll, content: content)
        } else {
            content
        }
    }
}

private struct TrackedScrollContent<C: View>: View {
    @ObservedObject var metrics: WorkspaceHeaderMetrics
    let scroll: WorkspaceScrollProgress
    let content: C

    var body: some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Offset from the resting position; the header slot is part of
                // the content insets, so this reads 0 at the top.
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scroll.update(offset: offset, gain: metrics.gain)
            }
    }
}

/// Trailing room row worth the collapse distance, so a list that just fills
/// the screen can still scroll far enough to minimize the header. Lists much
/// shorter than the screen collapse it partially; sizing the row from the
/// scroll geometry is a feedback loop (the list re-lays out one frame after
/// the room changes), so the row is a constant. Renders nothing without a
/// workspace header in the environment.
struct WorkspaceListFooter: View {
    @Environment(\.workspaceHeader) private var context

    var body: some View {
        if let context {
            FooterRoom(metrics: context.metrics)
        }
    }
}

private struct FooterRoom: View {
    @ObservedObject var metrics: WorkspaceHeaderMetrics

    var body: some View {
        Section {
            Color.clear
                .frame(height: metrics.gain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
        .listSectionMargins(.all, 0)
        .accessibilityHidden(true)
    }
}

/// Fixed-height slot above the content, so the scroll container never
/// resizes while the header inside it collapses; rows scroll through the
/// transparent part beneath the shrunken header.
struct WorkspaceHeaderSlot<Header: View>: View {
    @ObservedObject var metrics: WorkspaceHeaderMetrics
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(spacing: 0) {
            header()
            Spacer(minLength: 0)
        }
        .frame(height: metrics.expandedHeight)
    }
}

extension View {
    /// Lets this list drive the collapse of the motorcycle header above it.
    /// Without a workspace header in the environment this does nothing.
    func tracksWorkspaceHeader() -> some View {
        modifier(WorkspaceHeaderTracking())
    }
}
