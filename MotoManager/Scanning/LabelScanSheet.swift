import SwiftUI
import Vision
import VisionKit

/// Live QR scanner for printed part/storage-location labels. The first code
/// that parses as a label URL is delivered automatically — no tap needed, a
/// label carries exactly one QR. Only available on real hardware — gate on
/// `isSupported`, the simulator shows an unavailable state.
struct QRLabelScanner: UIViewControllerRepresentable {
    let onScan: (ScannedLabel) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (ScannedLabel) -> Void
        /// The sheet stays up through the dismissal animation — deliver once.
        private var hasDelivered = false

        init(onScan: @escaping (ScannedLabel) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            deliver(from: addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver(from: [item])
        }

        /// Foreign QR codes (payloads that aren't label URLs) are ignored so
        /// the camera keeps scanning instead of dismissing on the wrong code.
        private func deliver(from items: [RecognizedItem]) {
            guard !hasDelivered else { return }
            for item in items {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue,
                      let label = LabelWebLinks.parse(payload) else { continue }
                hasDelivered = true
                onScan(label)
                return
            }
        }
    }
}

/// Sheet wrapper around `QRLabelScanner`: point at a printed label's QR code
/// and the matching part or storage location is returned. Requires a real
/// device — the simulator has no camera, so it shows an unavailable state.
struct LabelScanSheet: View {
    let onResult: (ScannedLabel) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The camera controller is expensive to create — mounting it during the
    /// sheet presentation stalls the animation. Present the sheet with a
    /// loader first and mount the scanner one frame later; the camera feed
    /// covers the loader as soon as it is live.
    @State private var scannerMounted = false

    var body: some View {
        NavigationStack {
            Group {
                if QRLabelScanner.isSupported {
                    ZStack {
                        cameraLoader
                        if scannerMounted {
                            scanner
                        }
                    }
                    .task {
                        await Task.yield()
                        scannerMounted = true
                    }
                } else {
                    unavailable
                }
            }
            .navigationTitle("Etikett scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private var cameraLoader: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Kamera wird gestartet …")
                .scaledFont(13, weight: .semibold)
                .foregroundColor(Theme.Glass.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanner: some View {
        QRLabelScanner { label in
            onResult(label)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Text("Auf den QR-Code des Etiketts zielen")
                .scaledFont(13, weight: .semibold)
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
                .scaledFont(40)
                .foregroundColor(Theme.Glass.mutedText)
            Text("Kamera nicht verfügbar")
                .scaledFont(16, weight: .semibold)
                .foregroundColor(.white)
            Text("Der Scanner benötigt die Kamera eines echten Geräts.")
                .scaledFont(13)
                .foregroundColor(Theme.Glass.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
