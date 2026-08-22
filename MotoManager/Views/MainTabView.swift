import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @EnvironmentObject private var persistenceMonitor: PersistenceMonitor
    @EnvironmentObject private var syncEngine: SyncEngine
    @ObservedObject private var quickActions = QuickActionRouter.shared
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
                ProgressView("Garage wird geladen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = fleetVM.errorMessage {
                LoadFailureView(
                    title: "Garage konnte nicht geladen werden",
                    message: error,
                    retry: { await fleetVM.loadMotorcycles() }
                )
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
                .glassSheet()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .glassSheet()
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
        .alert(item: $persistenceMonitor.issue) { issue in
            Alert(
                title: Text(issue.title),
                message: Text(issue.message),
                dismissButton: .default(Text("OK"))
            )
        }
        // App Shortcut landed: jump to the owning tab and clear any chrome
        // sheet in the way; the tab view consumes the action itself.
        .onChange(of: quickActions.pending, initial: true) { _, action in
            guard let action else { return }
            showingGarage = false
            showingSettings = false
            switch action {
            case .addFuel: activeTab = .fuel
            case .scanPart: activeTab = .parts
            }
        }
    }

    // MARK: - Authenticated content

    @ViewBuilder
    private func screenStack(dVM: MotorcycleDetailViewModel) -> some View {
        // Native iOS 26 TabView with the Liquid Glass tab bar. Each screen owns
        // the system navigation bar (settings/add as toolbar items); transient
        // sync/refresh status lives in the system bottom accessory, which
        // morphs into the minimized tab bar on scroll.
        let showAccessory = StatusAccessoryBar.isActive(engine: syncEngine, viewModel: dVM)
        let tabs = TabView(selection: $activeTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.label, systemImage: tab.systemImage, value: tab) {
                    NavigationStack {
                        screen(for: tab, dVM: dVM)
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)

        Group {
            if #available(iOS 26.1, *) {
                // `isEnabled:` keeps the TabView's identity stable while the
                // accessory comes and goes.
                tabs.tabViewBottomAccessory(isEnabled: showAccessory) {
                    StatusAccessoryBar(viewModel: dVM)
                }
            } else if showAccessory {
                // iOS 26.0 has no `isEnabled:` — attach only while active.
                tabs.tabViewBottomAccessory {
                    StatusAccessoryBar(viewModel: dVM)
                }
            } else {
                tabs
            }
        }
        .tint(Theme.Colors.primary)
        // Tear down all four navigation stacks (including any pushed detail
        // referring to the previous bike's records) when the bike changes.
        .id(dVM.motorcycle.id)
    }

    @ViewBuilder
    private func screen(for tab: AppTab, dVM: MotorcycleDetailViewModel) -> some View {
        if tab != .parts, let error = dVM.errorMessage, !dVM.hasDisplayData {
            LoadFailureView(
                title: "Daten konnten nicht geladen werden",
                message: error,
                retry: { await dVM.reconnect() }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Einstellungen", systemImage: "gearshape") { showingSettings = true }
                }
            }
        } else {
            switch tab {
            case .fuel:
                FuelListView(viewModel: dVM)
            case .workshop:
                WorkshopView(viewModel: dVM)
            case .service:
                MaintenanceLogsView(viewModel: dVM, partsVM: partsVM)
            case .parts:
                PartsView(viewModel: partsVM, detailVM: dVM, motorcycle: dVM.motorcycle)
            }
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
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .glassEffect(.regular, in: Circle())
        }
        // Without this VoiceOver reads out the raw SF Symbol name.
        .accessibilityLabel("Einstellungen")
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

                Image(systemName: "motorcycle")
                    .scaledFont(60)
                    .foregroundStyle(Theme.Colors.primary)
            }
            .padding(.top, 40)

            VStack(spacing: Theme.Spacing.m) {
                Text("Deine Garage ist leer")
                    .scaledFont(28, weight: .bold, design: .rounded)

                Text("Füge dein erstes Motorrad hinzu, um Tankungen, Wartungen und Teile zu verwalten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            VStack(spacing: Theme.Spacing.l) {
                // Open the garage sheet, which hosts the add-motorcycle affordance,
                // rather than doing nothing.
                Button(action: onAdd) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Erstes Motorrad hinzufügen")
                    }
                }
                .glassActionButton(.primary, in: .roundedRectangle(radius: Theme.Radius.control))

                HStack(spacing: 20) {
                    Label("Tankungen", systemImage: "fuelpump.fill")
                    Label("Wartung", systemImage: "wrench.fill")
                    Label("Daten", systemImage: "bolt.fill")
                }
                .scaledFont(10, weight: .bold)
                .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(Theme.Spacing.l)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .padding(.horizontal, Theme.Spacing.l)

            Spacer()
        }
    }
}

private struct LoadFailureView: View {
    let title: String
    let message: String
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button {
                isRetrying = true
                Task {
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying { ProgressView() } else { Text("Erneut versuchen") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(MotorcycleViewModel())
        .environmentObject(PersistenceMonitor.shared)
}
