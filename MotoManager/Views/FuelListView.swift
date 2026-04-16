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
                        EmptyStateView(title: "No Fuel Logs", message: "Tapping the + button to record your first fill-up.")
                            .padding(.top, 100)
                    } else {
                        ForEach(fuelRecords) { record in
                            NavigationLink(destination: FuelDetailView(record: record)) {
                                FuelRow(record: record, averageConsumption: averageConsumption)
                                    .padding(.horizontal, Theme.Spacing.s)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                await viewModel.loadAllData()
            }
            
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.1))
                    .frame(width: 44, height: 44)

                consumptionIndicator
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(record.fuelAmount?.formatted() ?? "0") L")
                        .font(.headline)
                    if let consumption = record.fuelConsumption {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(String(format: "%.1f L/100", consumption))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Text(record.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let cost = record.cost {
                    Text("\(String(format: "%.2f", cost)) \(record.currency ?? "")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                Text("\(record.odo) km")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Radius.m)
    }

    @ViewBuilder
    private var consumptionIndicator: some View {
        if let consumption = record.fuelConsumption, averageConsumption > 0 {
            let diff = consumption - averageConsumption
            let isHigher = diff > 0.1 // Small threshold
            let isLower = diff < -0.1

            Image(systemName: isHigher ? "arrow.up.right.circle.fill" : (isLower ? "arrow.down.right.circle.fill" : "equal.circle.fill"))
                .foregroundColor(isHigher ? .orange : (isLower ? .green : .blue))
                .font(.title2)
        } else {
            Image(systemName: "fuelpump.fill")
                .foregroundColor(Theme.Colors.primary)
        }
    }
}
