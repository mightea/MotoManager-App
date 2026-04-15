import SwiftUI

struct MotorcycleRowView: View {
    let motorcycle: Motorcycle
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Main visual element - Floating Image
            ZStack(alignment: .bottomLeading) {
                if let imageUrl = motorcycle.image {
                    RemoteImageView(url: imageUrl)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
                } else {
                    fallbackImage
                }
                
                // Overlay Badges
                VStack {
                    HStack {
                        if motorcycle.isVeteran {
                            HStack(spacing: 4) {
                                Image(systemName: "medal.fill")
                                Text("VETERAN")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.m)
                
                // Content overlaying the image
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(motorcycle.model)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Text(motorcycle.make.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(2)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .padding(Theme.Spacing.l)
            }
            
            // Stats floating on the "glass"
            HStack(spacing: Theme.Spacing.xl) {
                GlassStatItem(icon: "gauge.with.dots", value: "\(motorcycle.latestOdo ?? motorcycle.initialOdo)", unit: "km")
                GlassStatItem(icon: "wrench.and.screwdriver", value: "\(motorcycle.maintenanceCount ?? 0)", unit: "svcs")
                GlassStatItem(icon: "exclamationmark.circle", value: "\(motorcycle.openIssues ?? 0)", unit: "issues", color: (motorcycle.openIssues ?? 0) > 0 ? .orange : .primary)
            }
            .padding(.horizontal, Theme.Spacing.s)
            
            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(.vertical, Theme.Spacing.s)
    }
    
    private var fallbackImage: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(height: 240)
            .overlay(
                Image(systemName: "bicycle")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.primary.opacity(0.3))
            )
    }
}

struct GlassStatItem: View {
    let icon: String
    let value: String
    let unit: String
    var color: Color = .primary
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Colors.primary)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }
}
