import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @State private var detailVM: MotorcycleDetailViewModel?
    @StateObject private var partsVM = PartsViewModel()
    @State private var activeTab: AppTab = .fuel
    @State private var showingGarage = false
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            LiquidBackgroundView().ignoresSafeArea()

            if let dVM = detailVM {
                screenStack(dVM: dVM)
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
        // Single load path keyed on the selected bike: fires on first appearance
        // and on every selection change, so the detail VM is created and loaded
        // exactly once per switch (previously onAppear + onChange + an inline
        // .task all fired, causing duplicate fetch storms).
        .task(id: fleetVM.selectedMotorcycle?.id) {
            guard let selected = fleetVM.selectedMotorcycle else { return }
            let dVM = MotorcycleDetailViewModel(motorcycle: selected)
            self.detailVM = dVM
            await dVM.reconnect()
        }
    }

    // MARK: - Authenticated content

    @ViewBuilder
    private func screenStack(dVM: MotorcycleDetailViewModel) -> some View {
        // Native iOS 26 TabView with the Liquid Glass tab bar. Scroll-to-minimize
        // is intentionally off: the offline banner + add button float above the
        // tab bar as background-free overlays (each screen's `bottomActionBar`),
        // and a minimizing bar would leave the button floating mid-screen.
        TabView(selection: $activeTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.label, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        screen(for: tab, dVM: dVM)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
            }
        }
        .tint(Theme.Colors.primary)
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
        case .parts:
            PartsView(viewModel: partsVM, detailVM: dVM, motorcycle: dVM.motorcycle)
        }
    }

    // MARK: - Empty fleet branch

    private var emptyFleetStack: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Compact glass chrome with settings access while the fleet is empty
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 110)
                        .glassEffect(.regular, in: Rectangle())
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

                EmptyFleetView(onAdd: { showingGarage = true })
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
                .glassEffect(.regular, in: Circle())
        }
    }
}

// MARK: - Empty fleet view

struct EmptyFleetView: View {
    /// Invoked by the primary CTA; the parent opens the garage sheet.
    var onAdd: () -> Void = {}

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
                // Open the garage sheet, which hosts the add-motorcycle affordance,
                // rather than doing nothing.
                Button(action: onAdd) {
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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
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
