import SwiftUI

enum HeaderType {
    case fuel, service, workshop
}

struct MotorcycleSummaryHeader: View {
    let motorcycle: Motorcycle
    let type: HeaderType
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Image with Gradient
            if let imageUrl = motorcycle.image {
                RemoteImageView(url: imageUrl)
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 280) // Increased height to flow behind nav bar
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.7), location: 0),
                                .init(color: .black.opacity(0.1), location: 0.5),
                                .init(color: .black.opacity(0.8), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Theme.Colors.primary.opacity(0.8)
                    .frame(height: 280)
            }
            
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Spacer() // Push content to bottom
                
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(motorcycle.model)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(motorcycle.make.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white.opacity(0.8))
                            .tracking(2)
                    }
                    Spacer()
                    
                    headerBadge
                }
                
                // Full-width stats
                HStack(spacing: 0) {
                    statsForType
                }
                .padding(.vertical, Theme.Spacing.m)
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.Radius.m)
            }
            .padding()
        }
        .frame(height: 280)
        .clipped()
        // No horizontal padding here to allow edge-to-edge flow if desired, 
        // but we'll apply it in the container for consistent list alignment.
    }
    
    @ViewBuilder
    private var headerBadge: some View {
        if motorcycle.isVeteran {
            HStack(spacing: 4) {
                Image(systemName: "medal.fill")
                Text("VETERAN")
            }
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
    
    @ViewBuilder
    private var statsForType: some View {
        switch type {
        case .fuel:
            StatView(icon: "fuelpump.fill", value: String(format: "%.1f", averageFuelConsumption), unit: "L/100", label: "Avg Fuel")
                .frame(maxWidth: .infinity)
            StatView(icon: "calendar", value: "\(fuelRecordsCount)", unit: "logs", label: "Total")
                .frame(maxWidth: .infinity)
            StatView(icon: "gauge.with.dots", value: "\(motorcycle.latestOdo ?? motorcycle.initialOdo)", unit: "km", label: "Odometer")
                .frame(maxWidth: .infinity)
            
        case .service:
            StatView(icon: "wrench.and.screwdriver", value: "\(serviceRecordsCount)", unit: "logs", label: "History")
                .frame(maxWidth: .infinity)
            StatView(icon: "exclamationmark.circle", value: "\(motorcycle.openIssues ?? 0)", unit: "open", label: "Issues", color: (motorcycle.openIssues ?? 0) > 0 ? .orange : .white)
                .frame(maxWidth: .infinity)
            StatView(icon: "gauge.with.dots", value: "\(motorcycle.latestOdo ?? motorcycle.initialOdo)", unit: "km", label: "Last Svc")
                .frame(maxWidth: .infinity)
            
        case .workshop:
            StatView(icon: "bolt.fill", value: "\(viewModel.torqueSpecs.count)", unit: "specs", label: "Torque")
                .frame(maxWidth: .infinity)
            StatView(icon: "wrench.fill", value: "\(uniqueToolCount)", unit: "tools", label: "Required")
                .frame(maxWidth: .infinity)
            StatView(icon: "doc.fill", value: "\(viewModel.documents.count)", unit: "docs", label: "Manuals")
                .frame(maxWidth: .infinity)
        }
    }
    
    // Helper stats
    private var fuelRecordsCount: Int {
        viewModel.maintenanceRecords.filter { $0.recordType.lowercased() == "fuel" }.count
    }
    
    private var serviceRecordsCount: Int {
        viewModel.maintenanceRecords.filter { $0.recordType.lowercased() != "fuel" }.count
    }
    
    private var averageFuelConsumption: Double {
        let fuels = viewModel.maintenanceRecords.filter { $0.recordType.lowercased() == "fuel" }
        guard !fuels.isEmpty else { return 0.0 }
        let totalConsumption = fuels.compactMap { $0.fuelConsumption }.reduce(0, +)
        let count = fuels.filter { $0.fuelConsumption != nil }.count
        return count > 0 ? totalConsumption / Double(count) : 0.0
    }
    
    private var uniqueToolCount: Int {
        Set(viewModel.torqueSpecs.compactMap { $0.toolSize }).count
    }
}

struct StatView: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    var color: Color = .white
    
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white.opacity(0.7))
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}
