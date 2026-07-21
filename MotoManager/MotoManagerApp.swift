//
//  MotoManagerApp.swift
//  MotoManager
//
//  Created by Tobias Herrmann on 15.04.2026.
//

import SwiftUI
import SwiftData

@main
struct MotoManagerApp: App {
    @StateObject private var connectivity = ConnectivityMonitor.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var persistenceMonitor = PersistenceMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(connectivity)
                .environmentObject(syncEngine)
                .environmentObject(persistenceMonitor)
                .modelContainer(PersistenceController.shared)
                .onChange(of: scenePhase) { _, phase in
                    // Flush pending changes whenever the app returns to the foreground.
                    if phase == .active {
                        syncEngine.requestSync(motorcycleIds: [])
                    }
                }
        }
    }
}
