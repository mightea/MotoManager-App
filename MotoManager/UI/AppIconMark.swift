import SwiftUI

/// In-app rendering of the MotoManager app icon (M + 4-band stripe on a
/// navy gradient). Used on the splash screen so the launch artwork matches
/// the home-screen icon. Mirrors `IconMotorcycle` in `AppIcon.jsx`.
struct AppIconMark: View {
    var size: CGFloat = 120
    var cornerRadius: CGFloat? = nil

    private let dakarBlue   = Color(red: 30/255,  green: 91/255,  blue: 255/255) // #1E5BFF
    private let dakarPlum   = Color(red: 91/255,  green: 29/255,  blue: 122/255) // #5B1D7A
    private let dakarSand   = Color(red: 232/255, green: 163/255, blue: 65/255)  // #E8A341
    private let dakarVerm   = Color(red: 255/255, green: 65/255,  blue: 36/255)  // #FF4124

    var body: some View {
        let radius = cornerRadius ?? (size * 0.227) // iOS squircle approximation
        ZStack {
            background
            shine
            mLetter
            stripe
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.30), radius: size * 0.10, x: 0, y: size * 0.05)
        .shadow(color: .black.opacity(0.20), radius: size * 0.04, x: 0, y: size * 0.02)
    }

    private var background: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 26/255, green: 21/255, blue: 48/255), location: 0.0),  // #1a1530
                .init(color: Color(red: 14/255, green: 10/255, blue: 28/255), location: 0.6),  // #0e0a1c
                .init(color: Color(red: 8/255,  green: 6/255,  blue: 18/255), location: 1.0)   // #080612
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var shine: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.16), .clear],
            center: UnitPoint(x: 0.30, y: 0.20),
            startRadius: 0,
            endRadius: size * 0.80
        )
        .blendMode(.plusLighter)
    }

    private var mLetter: some View {
        // The SVG places "M" at fontSize 780 in a 1024 viewBox (~76% of canvas).
        // Match that ratio with size * 0.76 and lock weight to .black for the
        // densest available glyph. Offset slightly upward to leave room for stripe.
        Text("M")
            .font(.system(size: size * 0.76, weight: .black))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, Color(red: 230/255, green: 233/255, blue: 240/255)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .tracking(-size * 0.04)
            .offset(y: -size * 0.04)
            .shadow(color: .black.opacity(0.5), radius: size * 0.014, x: 0, y: size * 0.016)
    }

    private var stripe: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    dakarBlue
                    dakarPlum
                    dakarSand
                    dakarVerm
                }
                Color.white.opacity(0.25)
                    .frame(height: size * 0.003)
            }
            .frame(height: size * 44 / 1024)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AppIconMark(size: 180)
        AppIconMark(size: 96)
        AppIconMark(size: 60)
    }
    .padding()
    .background(Color.black)
}
