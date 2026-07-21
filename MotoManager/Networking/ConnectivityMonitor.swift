import Foundation
import Network
import Combine

/// Publishes the device's online/offline state via `NWPathMonitor`.
/// The `SyncEngine` observes this to flush the outbox the moment connectivity
/// returns, and the UI uses it to show the offline/synced status.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()

    /// Starts optimistically `true` so the first launch attempts a sync; the
    /// monitor corrects it within a moment if the device is actually offline.
    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.motomanager.connectivity")

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOnline != online {
                    self.isOnline = online
                }
            }
        }
        monitor.start(queue: queue)
    }
}
