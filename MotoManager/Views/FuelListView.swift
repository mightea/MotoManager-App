import SwiftUI

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var showingAddFuel = false
    
    var fuelRecords: [MaintenanceRecord] {
        viewModel.maintenanceRecords.filter { $0.recordType.lowercased() == "fuel" }
    }
    
    var averageConsumption: Double {
        let fuels = fuelRecords.filter { $0.fuelConsumption != nil }
        guard !fuels.isEmpty else { return 0.0 }
        let total = fuels.compactMap { $0.fuelConsumption }.reduce(0, +)
        return total / Double(fuels.count)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .fuel, viewModel: viewModel)
                        .ignoresSafeArea(edges: .top)

                    if viewModel.isLoading && fuelRecords.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            GlassShimmerRow()
                                .padding(.horizontal, Theme.Spacing.s)
                        }
                    } else if fuelRecords.isEmpty && !viewModel.isLoading {
                        EmptyStateView(title: "No Fuel Logs", message: "Tapping the + button to record your first fill-up.", icon: "fuelpump.fill")
                            .padding(.top, 100)
                    } else {
                        ForEach(fuelRecords) { record in
                            NavigationLink(destination: FuelDetailView(record: record, viewModel: viewModel)) {
                                FuelRow(record: record, averageConsumption: averageConsumption)
                                    .padding(.horizontal, Theme.Spacing.s)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable {
                await viewModel.loadAllData()
            }
            .ignoresSafeArea(edges: .top)
            
            // FAB for Fuel
            Button(action: { showingAddFuel = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.Colors.primary)
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .padding(.trailing, Theme.Spacing.m)
            .padding(.bottom, 6)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
        }
    }
}

struct FuelListView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            FuelListView(viewModel: .mock)
        }
    }
}

struct FuelRow: View {
    let record: MaintenanceRecord
    let averageConsumption: Double
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left Side: Date & Amount
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                
                Text("\(record.fuelAmount?.formatted() ?? "0") Liters")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Right Side: Consumption (Main) & Trip/Odo
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    consumptionIndicator
                    
                    if let consumption = record.fuelConsumption {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", consumption))
                                .font(.system(size: 22, weight: .black, design: .rounded))
                            Text("L/100")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    } else {
                        Text("--.-")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
                
                HStack(spacing: 6) {
                    if let trip = record.tripDistance {
                        Text("\(Int(trip)) km trip")
                    }
                    Text("•")
                    Text("\(record.odo) km total")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Radius.m)
    }
    
    @ViewBuilder
    private var consumptionIndicator: some View {
        if let consumption = record.fuelConsumption, averageConsumption > 0 {
            let diff = consumption - averageConsumption
            let isHigher = diff > 0.1
            let isLower = diff < -0.1
            
            Image(systemName: isHigher ? "arrow.up.right" : (isLower ? "arrow.down.right" : "equal"))
                .font(.system(size: 14, weight: .black))
                .foregroundColor(isHigher ? .orange : (isLower ? .green : .blue))
        }
    }
}
