import CoreLocation
import Foundation

/// Thin async wrapper around `CLLocationManager` for one-shot "where am I now"
/// lookups (used when logging a fuel entry to detect the station). Requests
/// When-In-Use permission on demand. Follows the app's `static let shared`
/// service convention (see `ConnectivityMonitor`, `SyncEngine`).
@MainActor
final class LocationManager: NSObject {
    static let shared = LocationManager()

    enum LocationError: Error { case denied, unavailable }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Requests permission if still undetermined, then resolves a single current
    /// fix. Throws `.denied` when the user has refused, or the underlying
    /// CoreLocation error if the fix fails.
    func requestCurrentLocation() async throws -> CLLocation {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.denied
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            guard status != .notDetermined, let continuation = authContinuation else { return }
            authContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            if let location = locations.last {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}
