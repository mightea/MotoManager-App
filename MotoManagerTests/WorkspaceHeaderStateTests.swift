import Foundation
import Testing
@testable import MotoManager

struct WorkspaceHeaderStateTests {
    private func minimize(isMinimized: Bool = false, pastThreshold: Bool, maxOffset: CGFloat,
                          headerGain: CGFloat = 120) -> Bool {
        WorkspaceHeaderState.shouldMinimize(isMinimized: isMinimized, pastThreshold: pastThreshold,
                                            maxOffset: maxOffset, headerGain: headerGain)
    }

    @Test func staysExpandedAtTheTop() {
        #expect(minimize(pastThreshold: false, maxOffset: 2_000) == false)
        #expect(minimize(isMinimized: true, pastThreshold: false, maxOffset: 2_000) == false)
    }

    @Test func minimizesOnceScrolledWithEnoughContent() {
        #expect(minimize(pastThreshold: true, maxOffset: 600) == true)
    }

    @Test func shortListsKeepTheHeader() {
        // 60 points of scroll room disappear entirely once the header gives
        // back 120 points, so minimizing would immediately expand again.
        #expect(minimize(pastThreshold: true, maxOffset: 60) == false)
        #expect(minimize(pastThreshold: true, maxOffset: 140) == false)
        #expect(minimize(pastThreshold: true, maxOffset: 160) == true)
    }

    @Test func minimizedHeaderStaysWhileScrolledEvenWhenRoomShrinks() {
        #expect(minimize(isMinimized: true, pastThreshold: true, maxOffset: 40) == true)
    }

    @MainActor
    @Test func measuredHeightsDriveTheGain() {
        let state = WorkspaceHeaderState()
        #expect(state.headerGain == WorkspaceHeaderState.estimatedGain)
        state.recordHeight(200)
        #expect(state.headerGain == 130)
        state.scrolled(pastThreshold: true, maxOffset: 800)
        #expect(state.isMinimized)
        state.recordHeight(60)
        #expect(state.headerGain == 140)
        state.scrolled(pastThreshold: false, maxOffset: 800)
        #expect(!state.isMinimized)
    }
}
