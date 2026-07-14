import SwiftUI

struct GlassShimmerRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 150, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 100, height: 10)
            }
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 60, height: 14)
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .padding(.horizontal)
        .overlay {
            // Sweeping highlight — skipped entirely when Reduce Motion is on,
            // leaving a calm static skeleton.
            if !reduceMotion {
                GeometryReader { geo in
                    Color.white.opacity(0.1)
                        .mask(
                            Rectangle()
                                .fill(
                                    LinearGradient(gradient: Gradient(colors: [.clear, .white.opacity(0.5), .clear]), startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: 100)
                                .offset(x: -100 + (geo.size.width + 200) * phase)
                        )
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
