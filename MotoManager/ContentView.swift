import SwiftUI

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var fleetVM = MotorcycleViewModel()
    @StateObject private var upgradeManager = AppUpgradeManager.shared
    @State private var showSplash = true
    /// A connect link that arrived while signed in, waiting for confirmation.
    @State private var connectWhileSignedIn: ConnectLink?

    var body: some View {
        ZStack {
            Group {
                if upgradeManager.isBlocked {
                    // Hard upgrade requirement: out of support — no further
                    // backend requests until the app is updated.
                    UpdateRequiredView()
                } else if authVM.isAuthenticated && !authVM.isAwaitingGarage {
                    MainTabView()
                        .environmentObject(authVM)
                        .environmentObject(fleetVM)
                        .transition(.opacity)
                } else {
                    // Also shown right after a login, with "Garage wird
                    // geladen…", until the first garage load is done.
                    LoginView()
                        .environmentObject(authVM)
                        .transition(.opacity)
                }
            }
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        // Universal links from printed labels (https://<web origin>/parts/<id>,
        // /storage-locations/<id>): parked on the quick-action router until
        // the Teile tab is up — which also covers a cold launch and a link
        // that arrives before login. Foreign URLs are ignored.
        .onOpenURL { url in
            // Connect link from the webapp's settings: prefill the login.
            if let link = ConnectLink.parse(url) {
                if authVM.isAuthenticated {
                    connectWhileSignedIn = link
                } else {
                    ConnectLinkRouter.shared.pending = link
                }
                return
            }
            guard let label = LabelWebLinks.parse(url.absoluteString) else { return }
            QuickActionRouter.shared.pending = .openLabel(label)
        }
        .alert(
            "Mit diesem Konto verbinden?",
            isPresented: Binding(
                get: { connectWhileSignedIn != nil },
                set: { if !$0 { connectWhileSignedIn = nil } }
            ),
            presenting: connectWhileSignedIn
        ) { link in
            Button("Abmelden und verbinden", role: .destructive) {
                ConnectLinkRouter.shared.pending = link
                authVM.logout()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { link in
            Text("Du bist bereits angemeldet. Danach meldest du dich \(link.username.map { "als \($0) " } ?? "")bei \(link.displayHost) an. Noch nicht synchronisierte Änderungen gehen verloren.")
        }
        // Soft upgrade prompt, shown after the post-login check — held back
        // until the splash is gone so it doesn't pop up over it.
        .sheet(isPresented: Binding(
            get: { upgradeManager.showUpdatePrompt && !showSplash },
            set: { if !$0 { upgradeManager.showUpdatePrompt = false } }
        )) {
            AppUpdatePromptView()
        }
        // The launch-time fleet load is skipped while hard-blocked, so reload
        // once the block lifts ("Erneut prüfen" after an update or a lowered
        // requirement) — otherwise the garage would come up empty.
        .onChange(of: upgradeManager.isBlocked) { _, blocked in
            guard !blocked, authVM.isAuthenticated else { return }
            Task { await fleetVM.loadMotorcycles() }
        }
        // Drive fleet loading from the persistent root so splash dismissal does
        // not cancel the in-flight fetch. Re-runs on login/logout transitions.
        .task(id: authVM.isAuthenticated) {
            if authVM.isAuthenticated {
                // After a fresh login, hand over to the app once the garage is
                // loaded — or after a few seconds at most, so a slow load never
                // traps the user on the login screen (the app shows its own
                // loading state until the data arrives).
                let handOver = Task {
                    guard (try? await Task.sleep(for: .seconds(8))) != nil else { return }
                    finishLogin()
                }
                // Upgrade check first: a hard-blocked build must not fire the
                // fleet fetch (or any other request) anymore.
                await upgradeManager.check()
                if !upgradeManager.isBlocked {
                    await fleetVM.loadMotorcycles()
                }
                handOver.cancel()
                finishLogin()
            } else {
                // Logout wipes every cache; the fleet VM's in-memory state and
                // persisted selection/recents belong to that wipe too.
                fleetVM.clearUserState()
            }
            // Dismiss the splash once the initial state is actually ready, rather
            // than after a fixed 1.8s delay regardless of how fast loading was.
            if showSplash {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

extension ContentView {
    /// Fades from the login screen to the app (no-op when not logging in).
    private func finishLogin() {
        guard authVM.isAwaitingGarage else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            authVM.finishLogin()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
