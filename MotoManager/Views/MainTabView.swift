import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var fleetVM = MotorcycleViewModel()
    @State private var detailVM: MotorcycleDetailViewModel?
    
    var body: some View {
        NavigationView {
            Group {
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
                                Label("Settings", systemImage: "gear")
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
                } else if fleetVM.isLoading {
                    ProgressView("Loading fleet...")
                } else {
                    EmptyFleetView()
                }
            }
            .navigationTitle(fleetVM.selectedMotorcycle?.model ?? "MotoManager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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
        }
        .onAppear {
            Task {
                await fleetVM.loadMotorcycles()
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
}

struct EmptyFleetView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bicycle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Motorcycles Found")
                .font(.headline)
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView().environmentObject(AuthViewModel())
    }
}
