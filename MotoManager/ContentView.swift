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
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) {
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
