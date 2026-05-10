import SwiftUI
import MapKit

struct FuelDetailView: View {
    let recordId: Int
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    @State private var showingEdit = false
    @State private var region: MKCoordinateRegion?

    init(record: MaintenanceRecord, viewModel: MotorcycleDetailViewModel) {
        self.recordId = record.id
        self.viewModel = viewModel
    }

    /// Look up the latest version of the record from the viewmodel so the
    /// detail view auto-refreshes after an edit without manual prop drilling.
    private var record: MaintenanceRecord? {
        viewModel.maintenanceRecords.first { $0.id == recordId }
    }

    private func hasLocation(_ record: MaintenanceRecord) -> Bool {
        record.latitude != nil && record.longitude != nil
    }

    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()

            if let record {
                content(for: record)
            } else {
                ContentUnavailableView(
                    "Record not found",
                    systemImage: "fuelpump.slash.fill",
                    description: Text("This fuel record may have been removed.")
                )
            }
        }
        .navigationTitle("Fuel Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if record != nil {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let record {
                AddFuelView(viewModel: viewModel, existingRecord: record)
            }
        }
    }

    private func content(for record: MaintenanceRecord) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                // Hero Stats Section
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "fuelpump.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.Colors.primary)
                        .padding(.top)

                    Text("\(record.fuelAmount?.formatted() ?? "0") Liters")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(record.date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)

                // Technical Data Grid
                VStack(spacing: Theme.Spacing.m) {
                    DetailGridRow(label: "Consumption", value: String(format: "%.1f L/100km", record.fuelConsumption ?? 0.0), icon: "leaf.fill", color: .green)
                    DetailGridRow(label: "Trip Distance", value: "\(Int(record.tripDistance ?? 0)) km", icon: "arrow.triangle.turn.up.right.diamond.fill")
                    DetailGridRow(label: "Odometer", value: "\(record.odo) km", icon: "gauge.with.dots")
                    DetailGridRow(label: "Fuel Type", value: record.fuelType ?? "Standard", icon: "drop.fill")
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.Radius.l)

                // Cost Section
                VStack(spacing: Theme.Spacing.m) {
                    HStack {
                        Label("Transaction", systemImage: "creditcard.fill")
                            .font(.headline)
                        Spacer()
                    }

                    Divider()

                    HStack {
                        Text("Price per Unit")
                        Spacer()
                        Text("\(String(format: "%.2f", record.pricePerUnit ?? 0.0)) \(record.currency ?? "")")
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("Total Cost")
                        Spacer()
                        Text("\(String(format: "%.2f", record.cost ?? 0.0)) \(record.currency ?? "")")
                            .font(.title3)
                            .bold()
                            .foregroundColor(Theme.Colors.primary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.Radius.l)

                // Map Section
                if hasLocation(record), let lat = record.latitude, let lon = record.longitude {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack {
                            Label("Location", systemImage: "mappin.and.ellipse")
                                .font(.headline)
                            Spacer()
                            if let name = record.locationName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Map {
                            Marker(record.locationName ?? "Fuel Stop", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                .tint(Theme.Colors.primary)
                        }
                        .frame(height: 200)
                        .cornerRadius(Theme.Radius.m)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(Theme.Radius.l)
                } else if let location = record.locationName {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.red)
                        Text(location)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(Theme.Radius.m)
                }

                Spacer()
            }
            .padding()
        }
    }
}

struct DetailGridRow: View {
    let label: String
    let value: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.bold)
        }
    }
}

struct FuelDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FuelDetailView(
                record: MotorcycleDetailViewModel.mock.maintenanceRecords[0],
                viewModel: .mock
            )
        }
    }
}
