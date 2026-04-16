import SwiftUI

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            Group {
                if authVM.isAuthenticated {
                    MainTabView()
                        .environmentObject(authVM)
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
