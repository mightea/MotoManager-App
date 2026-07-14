import SwiftUI

/// Scans a motorcycle odometer with the live camera: point at the dashboard,
/// tap the odometer number, and its digits are returned as an editable value
/// (never an auto-committed reading). Requires a real device — the simulator has
/// no camera, so it shows an unavailable state.
struct OdometerScanSheet: View {
    let onResult: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if LiveOdometerScanner.isSupported {
                    scanner
                } else {
                    unavailable
                }
            }
            .navigationTitle("Kilometerstand scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var scanner: some View {
        LiveOdometerScanner { value in
            onResult(value)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Text("Auf den Kilometerstand zielen und antippen")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(.bottom, 40)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 40))
                .foregroundColor(Theme.Glass.mutedText)
            Text("Kamera nicht verfügbar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text("Der Scanner benötigt die Kamera eines echten Geräts.")
                .font(.system(size: 13))
                .foregroundColor(Theme.Glass.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
