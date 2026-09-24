import Foundation
import Testing
@testable import MotoManager

struct WorkspaceHeaderStateTests {
    @Test func progressFollowsTheScrolledDistance() {
        #expect(WorkspaceScrollProgress.progress(offset: 0, gain: 140) == 0)
        #expect(WorkspaceScrollProgress.progress(offset: 70, gain: 140) == 0.5)
        #expect(WorkspaceScrollProgress.progress(offset: 140, gain: 140) == 1)
    }

    @Test func progressIsClampedAtBothEnds() {
        // Pull-to-refresh overscroll must not stretch the header.
        #expect(WorkspaceScrollProgress.progress(offset: -80, gain: 140) == 0)
        #expect(WorkspaceScrollProgress.progress(offset: 900, gain: 140) == 1)
    }

    @Test func headerWithoutGainIsAlwaysMinimizedOnceScrolled() {
        #expect(WorkspaceScrollProgress.progress(offset: 0, gain: 0) == 0)
        #expect(WorkspaceScrollProgress.progress(offset: 1, gain: 0) == 1)
    }

    @MainActor
    @Test func metricsInterpolateBetweenTheMeasuredHeights() {
        let metrics = WorkspaceHeaderMetrics()
        metrics.expandedHeight = 200
        metrics.minimizedHeight = 60
        #expect(metrics.gain == 140)
        #expect(metrics.height(at: 0) == 200)
        #expect(metrics.height(at: 0.5) == 130)
        #expect(metrics.height(at: 1) == 60)

        let scroll = WorkspaceScrollProgress()
        scroll.update(offset: 35, gain: metrics.gain)
        #expect(scroll.progress == 0.25)
        scroll.update(offset: -10, gain: metrics.gain)
        #expect(scroll.progress == 0)
    }
}
