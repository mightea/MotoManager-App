import Foundation
import BRLMPrinterKit

/// A label printer found on the local network.
nonisolated struct DiscoveredPrinter: Identifiable, Sendable {
    let modelName: String
    let ipAddress: String
    var id: String { ipAddress }
}

nonisolated enum LabelPrintError: LocalizedError {
    case renderFailed
    case cannotConnect(String)
    case printFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Etikett konnte nicht erstellt werden."
        case .cannotConnect(let detail):
            return "Drucker nicht erreichbar (\(detail)). WLAN und IP-Adresse prüfen."
        case .printFailed(let detail):
            return "Drucken fehlgeschlagen (\(detail))."
        }
    }
}

/// Thin wrapper around BRLMPrinterKit for the Brother PT-E550W: network
/// discovery plus printing a rendered label bitmap. All SDK calls are
/// blocking network I/O, so everything runs off the main actor.
nonisolated enum LabelPrinterService {

    static let printerIPKey = "com.motomanager.labelPrinterIP"
    static let tapeKey = "com.motomanager.labelPrinterTape"

    /// Searches the local Wi-Fi for Brother printers (blocks for the search
    /// duration, hence detached). First call triggers iOS's local-network
    /// permission prompt.
    static func searchPrinters(seconds: TimeInterval = 8) async -> [DiscoveredPrinter] {
        await Task.detached(priority: .userInitiated) {
            let option = BRLMNetworkSearchOption()
            option.searchDuration = seconds
            let result = BRLMPrinterSearcher.startNetworkSearch(option) { _ in }
            return result.channels.compactMap { channel -> DiscoveredPrinter? in
                let ip = channel.channelInfo
                guard !ip.isEmpty else { return nil }
                let model = channel.extraInfo?[BRLMChannelExtraInfoKeyModelName] as? String
                return DiscoveredPrinter(modelName: model ?? "Brother-Drucker", ipAddress: ip)
            }
        }.value
    }

    /// Prints a rendered label. `pngData` is the 1-px-per-dot bitmap from
    /// `LabelRenderer`; passing data (not CGImage) keeps the hop to the
    /// detached task Sendable.
    static func printLabel(
        pngData: Data,
        printerIP: String,
        tape: LabelTape,
        copies: Int = 1
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("motomanager-label-\(UUID().uuidString).png")
            try pngData.write(to: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let channel = BRLMChannel(wifiIPAddress: printerIP)
            let openResult = BRLMPrinterDriverGenerator.open(channel)
            guard openResult.error.code == .noError, let driver = openResult.driver else {
                throw LabelPrintError.cannotConnect(String(describing: openResult.error.code))
            }
            defer { driver.closeChannel() }

            guard let settings = BRLMPTPrintSettings(defaultPrintSettingsWith: .PT_E550W) else {
                throw LabelPrintError.renderFailed
            }
            settings.labelSize = tape.brlmLabelSize
            settings.autoCut = true
            // The bitmap is already pure black/white at the tape's exact dot
            // height — threshold keeps modules crisp (no dithering).
            settings.halftone = .threshold
            settings.scaleMode = .fitPageAspect

            for _ in 0..<max(1, copies) {
                let printError = driver.printImage(with: fileURL, settings: settings)
                guard printError.code == .noError else {
                    throw LabelPrintError.printFailed(String(describing: printError.code))
                }
            }
        }.value
    }
}

nonisolated extension LabelTape {
    var brlmLabelSize: BRLMPTPrintSettingsLabelSize {
        switch self {
        case .mm12: return .width12mm
        case .mm18: return .width18mm
        case .mm24: return .width24mm
        }
    }
}
