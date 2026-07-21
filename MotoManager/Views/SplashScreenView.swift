import SwiftUI

/// Launch / splash view. Centered AppIcon + wordmark + tagline on a dark
/// navy background with three soft brand-color halos, terminated by the
/// 4-band motorsport stripe near the bottom.
///
/// Mirrors `motomanager-app/project/assets/screens/SplashScreen.jsx`.
struct SplashScreenView: View {
    @State private var markIn: Bool = false
    @State private var wordIn: Bool = false
    @State private var taglineIn: Bool = false
    @State private var stripeIn: Bool = false

    private let dakarBlue = Color(red: 30/255,  green: 91/255,  blue: 255/255)
    private let dakarPlum = Color(red: 91/255,  green: 29/255,  blue: 122/255)
    private let dakarSand = Color(red: 232/255, green: 163/255, blue: 65/255)
    private let dakarVerm = Color(red: 255/255, green: 65/255,  blue: 36/255)
    private let navy950   = Color(red: 10/255,  green: 7/255,   blue: 17/255)

    var body: some View {
        ZStack {
            navy950.ignoresSafeArea()
            halos.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                AppIconMark(size: 120)
                    .opacity(markIn ? 1 : 0)
                    .scaleEffect(markIn ? 1 : 0.86)
                Text("MotoManager")
                    .scaledFont(26, weight: .black)
                    .foregroundColor(.white)
                    .padding(.top, 28)
                    .opacity(wordIn ? 1 : 0)
                    .offset(y: wordIn ? 0 : 6)
                Text("DEINE DIGITALE GARAGE")
                    .scaledFont(11, weight: .semibold)
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 4)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 6)
                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                stripe
                    .opacity(stripeIn ? 1 : 0)
                    .scaleEffect(x: stripeIn ? 1 : 0, anchor: .center)
                    .padding(.bottom, 60)
                    .padding(.horizontal, 60)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { markIn = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.30)) { wordIn = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) { taglineIn = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.50)) { stripeIn = true }
        }
    }

    // MARK: - Halos

    private var halos: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Circle()
                    .fill(dakarBlue.opacity(0.30))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .offset(x: -w * 0.40, y: -h * 0.30)
                Circle()
                    .fill(dakarVerm.opacity(0.22))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .offset(x: w * 0.40, y: h * 0.30)
                Circle()
                    .fill(dakarPlum.opacity(0.45))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: 0, y: -h * 0.10)
            }
        }
    }

    // MARK: - Stripe

    private var stripe: some View {
        HStack(spacing: 0) {
            dakarBlue
            dakarPlum
            dakarSand
            dakarVerm
        }
        .frame(height: 3)
        .clipShape(Capsule())
    }
}

#Preview {
    SplashScreenView()
}
