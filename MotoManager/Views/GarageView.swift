import SwiftUI

struct GarageView: View {
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    headerSection
                    
                    if fleetVM.motorcycles.isEmpty && !fleetVM.isLoading {
                        EmptyFleetView()
                            .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: Theme.Spacing.m) {
                            ForEach(fleetVM.motorcycles) { motorcycle in
                                GarageCard(motorcycle: motorcycle) {
                                    fleetVM.selectMotorcycle(motorcycle)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
        }
        .navigationTitle("My Garage")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.bold)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("\(fleetVM.motorcycles.count) MOTORCYCLES")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundColor(.secondary)
            
            Text("Select Active Vehicle")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .padding(.top)
    }
}

struct GarageCard: View {
    let motorcycle: Motorcycle
    let action: () -> Void
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    
    var isSelected: Bool {
        fleetVM.selectedMotorcycle?.id == motorcycle.id
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Motorcycle Image Thumbnail
                ZStack(alignment: .bottomLeading) {
                    if let imageUrl = motorcycle.image {
                        RemoteImageView(url: imageUrl)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 100)
                            .clipped()
                    } else {
                        Theme.Colors.primary.opacity(0.2)
                            .frame(width: 120, height: 100)
                            .overlay(
                                Image(systemName: "bicycle")
                                    .font(.title)
                                    .foregroundColor(Theme.Colors.primary)
                            )
                    }
                    
                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(motorcycle.make.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(Theme.Colors.primary)
                    
                    Text(motorcycle.model)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Label("\(motorcycle.latestOdo ?? motorcycle.initialOdo) km", systemImage: "gauge.with.dots")
                        if let year = motorcycle.modelYear {
                            Label("\(year)", systemImage: "calendar")
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .padding(.leading, Theme.Spacing.m)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.trailing)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(isSelected ? Theme.Colors.primary.opacity(0.5) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(), value: isSelected)
    }
}

struct GarageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GarageView().environmentObject(MotorcycleViewModel())
        }
    }
}
