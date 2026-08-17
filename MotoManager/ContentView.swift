import SwiftUI

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var fleetVM = MotorcycleViewModel()
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            Group {
                if authVM.isAuthenticated {
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
        // Drive fleet loading from the persistent root so splash dismissal does
        // not cancel the in-flight fetch. Re-runs on login/logout transitions.
        .task(id: authVM.isAuthenticated) {
            if authVM.isAuthenticated {
                await fleetVM.loadMotorcycles()
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
