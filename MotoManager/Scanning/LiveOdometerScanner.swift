import SwiftUI
import VisionKit

/// Live "point at the odometer" scanner. Recognised numbers are highlighted; the
/// user taps the odometer window and its digits are returned. Only available on
/// real hardware (camera + Neural Engine) — gate on `isSupported` and fall back
/// to the photo picker on the simulator.
struct LiveOdometerScanner: UIViewControllerRepresentable {
    let onPick: (Int) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
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

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPick: (Int) -> Void
        init(onPick: @escaping (Int) -> Void) { self.onPick = onPick }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case let .text(text) = item,
                  let value = Self.odometer(from: text.transcript) else { return }
            onPick(value)
        }

        /// The longest 4–7 digit run in the tapped label (skips the 3-digit trip
        /// meter and any stray dial marks caught in the same highlight).
        static func odometer(from string: String) -> Int? {
            string.split(whereSeparator: { !$0.isNumber })
                .map(String.init)
                .filter { (4...7).contains($0.count) }
                .max(by: { $0.count < $1.count })
                .flatMap { Int($0) }
        }
    }
}
