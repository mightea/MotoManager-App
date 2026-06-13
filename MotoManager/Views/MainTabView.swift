import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @State private var detailVM: MotorcycleDetailViewModel?
    @State private var activeTab: AppTab = .fuel
    @State private var showingGarage = false
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            LiquidBackgroundView().ignoresSafeArea()

            if let dVM = detailVM {
                screenStack(dVM: dVM)
                    .task { await dVM.loadAllData() }
            } else if fleetVM.isLoading {
                ProgressView("Loading fleet...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyFleetStack
            }

            VStack(spacing: 0) {
                MotorsportStripe()
                Spacer()
            }
            .ignoresSafeArea()
        }
        .environment(\.chromeActions, ChromeActions(
            openGarage: { showingGarage = true },
            openSettings: { showingSettings = true }
        ))
        .sheet(isPresented: $showingGarage) {
            GarageView()
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let selected = fleetVM.selectedMotorcycle {
                self.detailVM = MotorcycleDetailViewModel(motorcycle: selected)
            }
        }
        .onChange(of: fleetVM.selectedMotorcycle?.id) { _, _ in
            if let selected = fleetVM.selectedMotorcycle {
                let dVM = MotorcycleDetailViewModel(motorcycle: selected)
                self.detailVM = dVM
                Task { await dVM.loadAllData() }
            }
        }
    }

    // MARK: - Authenticated content

    @ViewBuilder
    private func screenStack(dVM: MotorcycleDetailViewModel) -> some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                screen(for: activeTab, dVM: dVM)
                    .toolbar(.hidden, for: .navigationBar)
            }

            VStack(spacing: 10) {
                RefreshBanner(viewModel: dVM)
                GlassTabBar(selection: $activeTab)
                    .padding(.bottom, 18)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab, dVM: MotorcycleDetailViewModel) -> some View {
        switch tab {
        case .fuel:
            FuelListView(viewModel: dVM)
        case .workshop:
            WorkshopView(viewModel: dVM)
        case .service:
            MaintenanceLogsView(viewModel: dVM)
        }
    }

    // MARK: - Empty fleet branch

    private var emptyFleetStack: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Compact glass chrome with settings access while the fleet is empty
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 110)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                        )
                    HStack {
                        Spacer()
                        glassIconButton(systemImage: "gearshape.fill") {
                            showingSettings = true
                        }
                        .padding(.trailing, Theme.Spacing.m)
                        .padding(.top, Theme.Spacing.l)
                    }
                }
                .ignoresSafeArea(edges: .top)

                EmptyFleetView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func glassIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        }
    }
}

// MARK: - Empty fleet view

struct EmptyFleetView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.18))
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

            VStack(spacing: Theme.Spacing.l) {
                Button(action: {}) {
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

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(MotorcycleViewModel())
}
