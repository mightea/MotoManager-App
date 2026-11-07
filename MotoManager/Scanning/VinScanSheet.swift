import SwiftUI
import VisionKit

/// Recognises a vehicle identification number in the live camera feed: the
/// 17-character VIN on the type plate or frame, or the 6–8 digit frame
/// number stamped on pre-1981 bikes. A full VIN is delivered as soon as it
/// is read (the pattern is unambiguous); a bare digit run needs a tap, since
/// a dashboard shows plenty of other numbers.
struct LiveVinScanner: UIViewControllerRepresentable {
    let onPick: (String) -> Void

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
        let onPick: (String) -> Void
        private var hasDelivered = false

        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case let .text(text) = item, let vin = VinRecognizer.vin(in: text.transcript) else { continue }
                deliver(vin)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case let .text(text) = item else { return }
            if let vin = VinRecognizer.vin(in: text.transcript) ?? VinRecognizer.frameNumber(in: text.transcript) {
                deliver(vin)
            }
        }

        private func deliver(_ value: String) {
            guard !hasDelivered else { return }
            hasDelivered = true
            onPick(value)
        }
    }
}

/// Pure text helpers behind the scanner (unit-tested).
nonisolated enum VinRecognizer {
    /// A 17-character VIN: letters except I, O and Q, plus digits. OCR often
    /// confuses O/0 and I/1, so those are normalised to the digits a VIN can
    /// actually contain before matching.
    static func vin(in text: String) -> String? {
        let normalised = text.uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "Q", with: "0")
            .filter { !$0.isWhitespace }
        guard let range = normalised.firstRange(of: /[A-HJ-NPR-Z0-9]{17}/) else { return nil }
        return String(normalised[range])
    }

    /// The longest 6–8 digit run in the tapped label (classic frame numbers).
    static func frameNumber(in text: String) -> String? {
        text.split(whereSeparator: { !$0.isNumber })
            .map(String.init)
            .filter { (6...8).contains($0.count) }
            .max(by: { $0.count < $1.count })
    }
}

/// Sheet wrapper around `LiveVinScanner`. Requires a real device — the
/// simulator has no camera, so it shows an unavailable state.
struct VinScanSheet: View {
    let onResult: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if LiveVinScanner.isSupported {
                    scanner
                } else {
                    unavailable
                }
            }
            .navigationTitle("Fahrgestellnummer scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Abbrechen")
                }
            }
        }
    }

    private var scanner: some View {
        LiveVinScanner { value in
            onResult(value)
            dismiss()
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Text("Auf Typenschild oder Rahmennummer zielen – eine Rahmennummer antippen")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.6)))
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .scaledFont(40)
                .foregroundStyle(Theme.Glass.mutedText)
            Text("Kamera nicht verfügbar")
                .scaledFont(16, weight: .semibold)
            Text("Der Scanner benötigt die Kamera eines echten Geräts.")
                .scaledFont(13)
                .foregroundStyle(Theme.Glass.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
