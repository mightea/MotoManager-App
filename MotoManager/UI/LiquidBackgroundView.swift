import SwiftUI

struct LiquidBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            
            // Animated blobs for the "liquid" feel
            Circle()
                .fill(Theme.Colors.primary.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(x: animate ? 100 : -100, y: animate ? -200 : -100)
            
            Circle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 50)
                .offset(x: animate ? -150 : 50, y: animate ? 200 : 100)
            
            Circle()
                .fill(Color.cyan.opacity(0.1))
                .frame(width: 350, height: 350)
                .blur(radius: 70)
                .offset(x: animate ? 50 : 150, y: animate ? -50 : 250)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}
