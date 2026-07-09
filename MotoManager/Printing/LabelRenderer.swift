import UIKit
import CoreImage.CIFilterBuiltins

// Label printing for the Brother PT-E550W (180 dpi, continuous TZe tape).
// Mirrors the webapp's printable labels (`part-label.tsx` /
// `storage-location-label.tsx`): a QR code linking to the entity's web page
// plus the text needed to identify the physical thing.

/// What goes on a printed label.
nonisolated struct LabelContent {
    /// Absolute URL the QR code points at (the entity's web page).
    var url: String
    /// Part number — rendered bold/monospaced. Nil for storage locations.
    var code: String?
    /// Part or location name.
    var title: String
    /// Manufacturer · fitment, or the location path ("Garage › Regal A").
    var subtitle: String?
    /// "MOTOMANAGER · TEIL #42" — matches the webapp label footer.
    var footer: String
}

/// Builds the absolute web URLs the printed QR codes point at. The webapp is
/// a separate origin from the API (`NetworkManager.baseURL`), so this is its
/// own setting with the deployed webapp as default.
nonisolated enum LabelWebLinks {
    static let originKey = "com.motomanager.labelWebOrigin"
    static let defaultOrigin = "https://moto.herrmann.ltd"

    static var origin: String {
        let stored = UserDefaults.standard.string(forKey: originKey)
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = trimmed.isEmpty ? defaultOrigin : trimmed
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    static func partURL(serverId: Int) -> String { "\(origin)/parts/\(serverId)" }
    static func storageLocationURL(serverId: Int) -> String { "\(origin)/storage-locations/\(serverId)" }
}

/// TZe tape widths offered for printing. `printableDots` is the printable
/// height at the PT-E550W's 180 dpi — the print area is narrower than the
/// physical tape (e.g. 18.1 mm on 24 mm tape).
nonisolated enum LabelTape: String, CaseIterable, Identifiable {
    case mm12
    case mm18
    case mm24

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mm12: return "12 mm"
        case .mm18: return "18 mm"
        case .mm24: return "24 mm"
        }
    }

    var printableDots: Int {
        switch self {
        case .mm12: return 70
        case .mm18: return 112
        case .mm24: return 128
        }
    }
}

/// Renders a `LabelContent` into a bitmap sized for the tape's printable
/// height: 1 pixel = 1 printer dot, pure black on white (the printer
/// thresholds to monochrome, so no grays).
nonisolated enum LabelRenderer {

    static func render(content: LabelContent, tape: LabelTape) -> UIImage? {
        let height = CGFloat(tape.printableDots)
        // All metrics are designed against the 24 mm tape (128 dots) and
        // scaled down for narrower tapes.
        let s = height / 128

        let qrInset = (4 * s).rounded()
        let qrSide = height - 2 * qrInset
        guard let qr = qrImage(for: content.url, side: qrSide) else { return nil }

        let lines = textLines(for: content, scale: s)
        let lineSpacing = (3 * s).rounded()
        let maxTextWidth = (600 * s).rounded()
        let textWidth = min(
            maxTextWidth,
            lines.map { ceil($0.size().width) }.max() ?? 0
        )
        let textHeight = lines.map { ceil($0.size().height) }.reduce(0, +)
            + lineSpacing * CGFloat(max(0, lines.count - 1))

        let gap = (10 * s).rounded()
        let textX = qrInset + qrSide + gap
        let width = ceil(textX + textWidth + 8 * s)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // QR modules were scaled by an integer factor already; draw
            // centered in its slot without resampling.
            ctx.cgContext.interpolationQuality = .none
            let qrRect = CGRect(
                x: qrInset + (qrSide - qr.size.width) / 2,
                y: qrInset + (qrSide - qr.size.height) / 2,
                width: qr.size.width,
                height: qr.size.height
            )
            qr.draw(in: qrRect)

            var y = ((height - textHeight) / 2).rounded()
            for line in lines {
                let lineHeight = ceil(line.size().height)
                line.draw(
                    with: CGRect(x: textX, y: y, width: textWidth, height: lineHeight),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    context: nil
                )
                y += lineHeight + lineSpacing
            }
        }
    }

    // MARK: - Pieces

    private static func textLines(for content: LabelContent, scale s: CGFloat) -> [NSAttributedString] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        func line(_ text: String, font: UIFont, kern: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.black,
                .kern: kern,
                .paragraphStyle: paragraph,
            ])
        }

        var lines: [NSAttributedString] = []
        if let code = content.code, !code.isEmpty {
            lines.append(line(code, font: .monospacedSystemFont(ofSize: 16 * s, weight: .bold), kern: 0.5 * s))
        }
        lines.append(line(content.title.uppercased(), font: .systemFont(ofSize: 18 * s, weight: .heavy)))
        if let subtitle = content.subtitle, !subtitle.isEmpty {
            lines.append(line(subtitle, font: .systemFont(ofSize: 12 * s, weight: .medium)))
        }
        lines.append(line(content.footer.uppercased(), font: .monospacedSystemFont(ofSize: 9 * s, weight: .semibold), kern: 1.2 * s))
        return lines
    }

    /// QR code at error correction level M (same as the webapp), scaled by an
    /// integer factor so every module stays a crisp square of whole dots.
    private static func qrImage(for text: String, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let moduleCount = output.extent.width
        guard moduleCount > 0 else { return nil }
        let factor = max(1, (side / moduleCount).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
