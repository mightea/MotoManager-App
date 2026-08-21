import SwiftUI

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var fleetVM = MotorcycleViewModel()
    @StateObject private var upgradeManager = AppUpgradeManager.shared
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if upgradeManager.isBlocked {
                    // Hard upgrade requirement: out of support — no further
                    // backend requests until the app is updated.
                    UpdateRequiredView()
                } else if authVM.isAuthenticated {
                    MainTabView()
                        .environmentObject(authVM)
                        .environmentObject(fleetVM)
                } else {
                    LoginView()
                        .environmentObject(authVM)
                }
            }
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        // Soft upgrade reminder, shown after the post-login check.
        .overlay(alignment: .top) {
            AppUpdateToast()
                .opacity(showSplash ? 0 : 1)
                .animation(.spring(duration: 0.3), value: upgradeManager.showUpdateToast)
        }
        // The launch-time fleet load is skipped while hard-blocked, so reload
        // once the block lifts ("Erneut prüfen" after an update or a lowered
        // requirement) — otherwise the garage would come up empty.
        .onChange(of: upgradeManager.isBlocked) { _, blocked in
            guard !blocked, authVM.isAuthenticated else { return }
            Task { await fleetVM.loadMotorcycles() }
        }
        // Drive fleet loading from the persistent root so splash dismissal does
        // not cancel the in-flight fetch. Re-runs on login/logout transitions.
        .task(id: authVM.isAuthenticated) {
            if authVM.isAuthenticated {
                // Upgrade check first: a hard-blocked build must not fire the
                // fleet fetch (or any other request) anymore.
                await upgradeManager.check()
                if !upgradeManager.isBlocked {
                    await fleetVM.loadMotorcycles()
                }
            } else {
                // Logout wipes every cache; the fleet VM's in-memory state and
                // persisted selection/recents belong to that wipe too.
                fleetVM.clearUserState()
            }
            // Dismiss the splash once the initial state is actually ready, rather
            // than after a fixed 1.8s delay regardless of how fast loading was.
            if showSplash {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
