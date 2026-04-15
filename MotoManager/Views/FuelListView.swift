import SwiftUI

struct FuelListView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var showingAddFuel = false
    
    var fuelRecords: [MaintenanceRecord] {
        viewModel.maintenanceRecords.filter { $0.recordType.lowercased() == "fuel" }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    if fuelRecords.isEmpty && !viewModel.isLoading {
                        EmptyStateView(title: "No Fuel Logs", message: "Tapping the + button to record your first fill-up.")
                            .padding(.top, 100)
                    } else {
                        ForEach(fuelRecords) { record in
                            FuelRow(record: record)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, 100)
            }
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
            .padding()
        }
        .sheet(isPresented: $showingAddFuel) {
            AddFuelView(viewModel: viewModel)
        }
    }
}

struct FuelRow: View {
    let record: MaintenanceRecord
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "fuelpump.fill")
                    .foregroundColor(Theme.Colors.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.fuelAmount?.formatted() ?? "0") L")
                    .font(.headline)
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
        .padding(.horizontal)
    }
}
