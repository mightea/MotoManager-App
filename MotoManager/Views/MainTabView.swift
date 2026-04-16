import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @State private var detailVM: MotorcycleDetailViewModel?
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let dVM = detailVM {
                    TabView {
                        FuelListView(viewModel: dVM)
                            .tabItem {
                                Label("Fuel", systemImage: "fuelpump.fill")
                            }
                        
                        MaintenanceLogsView(viewModel: dVM)
                            .tabItem {
                                Label("Service", systemImage: "wrench.and.screwdriver.fill")
                            }
                        
                        TorqueSpecsView(viewModel: dVM)
                            .tabItem {
                                Label("Torque", systemImage: "bolt.fill")
                            }
                        
                        DocumentsView(viewModel: dVM)
                            .tabItem {
                                Label("Docs", systemImage: "doc.fill")
                            }
                        
                        SettingsView()
                            .tabItem {
                                Label("Settings", systemImage: "gearshape.fill")
                            }
                    }
                    .background(LiquidBackgroundView().ignoresSafeArea())
                    .onAppear {
                        // Restore normal appearance
                        let appearance = UITabBarAppearance()
                        appearance.configureWithDefaultBackground()
                        UITabBar.appearance().standardAppearance = appearance
                        UITabBar.appearance().scrollEdgeAppearance = appearance
                    }
                    .task {
                        await dVM.loadAllData()
                    }
                } else if fleetVM.isLoading {
                    ProgressView("Loading fleet...")
                } else {
                    // Always show TabView so Settings is accessible even if fleet is empty
                    TabView {
                        ZStack {
                            LiquidBackgroundView().ignoresSafeArea()
                            EmptyFleetView()
                        }
                        .tabItem {
                            Label("Garage", systemImage: "bicycle")
                        }
                        
                        SettingsView()
                            .tabItem {
                                Label("Settings", systemImage: "gearshape.fill")
                            }
                    }
                }
            }
            .navigationTitle(fleetVM.selectedMotorcycle?.model ?? "MotoManager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    fleetMenu
                }
            }
        }
        .onAppear {
            // If already loaded and selected from splash, initialize detailVM
            if let selected = fleetVM.selectedMotorcycle {
                self.detailVM = MotorcycleDetailViewModel(motorcycle: selected)
            }
        }
        .onChange(of: fleetVM.selectedMotorcycle?.id) { _ in
            if let selected = fleetVM.selectedMotorcycle {
                let dVM = MotorcycleDetailViewModel(motorcycle: selected)
                self.detailVM = dVM
                Task {
                    await dVM.loadAllData()
                }
            }
        }
    }
    
    @ViewBuilder
    private var fleetMenu: some View {
        Menu {
            ForEach(fleetVM.motorcycles) { moto in
                Button(action: { fleetVM.selectMotorcycle(moto) }) {
                    HStack {
                        Text("\(moto.make) \(moto.model)")
                        if moto.id == fleetVM.selectedMotorcycle?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.headline)
                .foregroundColor(Theme.Colors.primary)
        }
    }
}

struct EmptyFleetView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Hero Icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.1))
                    .frame(width: 140, height: 140)
                
                Image(systemName: "bicycle")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.primary)
            }
            .padding(.top, 40)
            
            VStack(spacing: Theme.Spacing.m) {
                Text("Your Garage is Empty")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Start tracking your fleet by adding your first motorcycle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            
            // Premium CTA Card
            VStack(spacing: Theme.Spacing.l) {
                Button(action: {
                    // Action to add motorcycle (placeholder)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Your First Motorcycle")
                    }
                }
                .buttonStyle(ModernButtonStyle())
                
                HStack(spacing: 20) {
                    Label("Fuel Logs", systemImage: "fuelpump.fill")
                    Label("Service", systemImage: "wrench.fill")
                    Label("Specs", systemImage: "bolt.fill")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(Theme.Spacing.l)
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.l)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.l)
            
            Spacer()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView().environmentObject(AuthViewModel())
    }
}
