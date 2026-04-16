import SwiftUI

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var body: some View {
        ZStack {
            // Branded background for splash
            LinearGradient(
                gradient: Gradient(colors: [Theme.Colors.primary.opacity(0.1), Theme.Colors.background]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            LiquidBackgroundView().ignoresSafeArea()
            
            VStack {
                VStack(spacing: 20) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 100))
                        .foregroundColor(Theme.Colors.primary)
                        .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Text("MotoManager")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Premium Fleet Management")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(4)
                        .textCase(.uppercase)
                }
                .scaleEffect(size)
                .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0)) {
                self.size = 1.0
                self.opacity = 1.0
            }
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
    }
}
