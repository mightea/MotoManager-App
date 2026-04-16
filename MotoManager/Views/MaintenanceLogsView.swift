import SwiftUI

struct MaintenanceLogsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    
    var serviceRecords: [MaintenanceRecord] {
        viewModel.maintenanceRecords.filter { $0.recordType.lowercased() != "fuel" }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .service, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)
                
                if viewModel.isLoading && serviceRecords.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        GlassShimmerRow()
                            .padding(.horizontal, Theme.Spacing.s)
                    }
                } else if serviceRecords.isEmpty && !viewModel.isLoading {
                    EmptyStateView(title: "No Service Logs", message: "Maintenance and repair logs will appear here.", icon: "wrench.and.screwdriver.fill")
                        .padding(.top, 100)
                } else {
                    ForEach(serviceRecords) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                let displayDescription = (record.description?.isEmpty ?? true) ? (record.summary ?? record.recordType.capitalized) : record.description!
                                
                                Text(displayDescription)
                                    .font(.headline)
                                Text("\(record.odo) km • \(record.date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let cost = record.cost {
                                Text("\(String(format: "%.2f", cost)) \(record.currency ?? "")")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(Theme.Radius.m)
                        .padding(.horizontal, Theme.Spacing.s)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .refreshable {
            await viewModel.loadAllData()
        }
    }
}

struct MaintenanceLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            MaintenanceLogsView(viewModel: .mock)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var icon: String = "bicycle.circle.fill"
    
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.05))
                    .frame(width: 120, height: 120)
                
                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(Theme.Colors.primary.opacity(0.6))
                    .shadow(color: Theme.Colors.primary.opacity(0.1), radius: 10)
            }
            .padding(.bottom, Theme.Spacing.s)
            
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(Theme.Spacing.l)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Radius.l)
        .padding(.horizontal, Theme.Spacing.l)
    }
}
