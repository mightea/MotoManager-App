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

    // Always the webapp's real routes — the QR must open in any camera app
    // without redirects. (A short-URL experiment bought one QR version but
    // broke that guarantee; don't repeat it.)
    static func partURL(serverId: Int) -> String { "\(origin)/parts/\(serverId)" }
    static func storageLocationURL(serverId: Int) -> String { "\(origin)/storage-locations/\(serverId)" }

    /// Parses a scanned QR payload back into the entity its label points at.
    /// Deliberately ignores the host: labels printed under an older or dev
    /// `labelWebOrigin` must keep scanning after the setting changes, and the
    /// path ids are server ids either way. Requires an http(s) URL with
    /// exactly `/<resource>/<id>` so arbitrary QR payloads don't match.
    static func parse(_ payload: String) -> ScannedLabel? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, let id = Int(components[1]), id > 0 else { return nil }
        switch components[0] {
        case "parts": return .part(serverId: id)
        case "storage-locations": return .storageLocation(serverId: id)
        default: return nil
        }
    }
}

/// A part or storage-location label identified from a scanned QR code.
nonisolated enum ScannedLabel: Equatable {
    case part(serverId: Int)
    case storageLocation(serverId: Int)
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

    /// Off-main render for UI callers: the QR pipeline (CIFilter + CIContext)
    /// is slow enough to visibly stall a sheet presentation.
    static func renderAsync(content: LabelContent, tape: LabelTape) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            render(content: content, tape: tape)
        }.value
    }

    /// The bitmap as sent to the printer: rotated 90° so its width spans the
    /// tape's printable dots and its height runs along the feed. Combined
    /// with `.actualSize` printing this maps 1 pixel to 1 printer dot — no
    /// SDK-side scaling that could shrink the label (see the 2026-07 sample
    /// where `fitPageAspect` printed at roughly half the tape height).
    static func renderPrintAsync(content: LabelContent, tape: LabelTape) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            render(content: content, tape: tape).map(rotatedForTape)
        }.value
    }

    private static func rotatedForTape(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.interpolationQuality = .none
            ctx.cgContext.translateBy(x: size.width, y: 0)
            ctx.cgContext.rotate(by: .pi / 2)
            image.draw(at: .zero)
        }
    }

    static func render(content: LabelContent, tape: LabelTape) -> UIImage? {
        let height = CGFloat(tape.printableDots)
        // All metrics are designed against the 24 mm tape (128 dots) and
        // scaled down for narrower tapes.
        let s = height / 128

        // No inset: the QR spans the full printable height (the physical tape
        // is wider than the print area, so the tape itself provides the quiet
        // zone). Integer module scaling below still decides the exact size.
        let qrInset: CGFloat = 0
        let qrSide = height - 2 * qrInset
        guard let qr = qrImage(for: content.url, side: qrSide) else { return nil }

        // Two-pass text sizing: measure the block at the design scale, then
        // rescale the fonts so the block fills the printable height (2-dot
        // margin per side) regardless of how many lines this label has —
        // location labels with 2-3 lines get markedly bigger type than a
        // 4-line part label. Clamped so overly tall blocks shrink to fit and
        // sparse labels don't become grotesque.
        func blockHeight(_ lines: [NSAttributedString], spacing: CGFloat) -> CGFloat {
            lines.map { ceil($0.size().height) }.reduce(0, +)
                + spacing * CGFloat(max(0, lines.count - 1))
        }
        let baseBlock = blockHeight(textLines(for: content, scale: s), spacing: (3 * s).rounded())
        let fill = min(2.0, max(0.6, (height - 4) / max(1, baseBlock)))
        let ts = s * fill

        let lines = textLines(for: content, scale: ts)
        let lineSpacing = (3 * ts).rounded()
        let maxTextWidth = (600 * ts).rounded()
        let textWidth = min(
            maxTextWidth,
            lines.map { ceil($0.size().width) }.max() ?? 0
        )
        let textHeight = blockHeight(lines, spacing: lineSpacing)

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
            lines.append(line(code, font: .monospacedSystemFont(ofSize: 24 * s, weight: .bold), kern: 0.5 * s))
        }
        lines.append(line(content.title.uppercased(), font: .systemFont(ofSize: 34 * s, weight: .heavy)))
        if let subtitle = content.subtitle, !subtitle.isEmpty {
            lines.append(line(subtitle, font: .systemFont(ofSize: 20 * s, weight: .medium)))
        }
        lines.append(line(content.footer.uppercased(), font: .monospacedSystemFont(ofSize: 14 * s, weight: .semibold), kern: 1.2 * s))
        return lines
    }

    /// QR code scaled by an integer factor so every module stays a crisp
    /// square of whole dots. Error correction L (webapp uses M): fewer
    /// modules mean a bigger integer factor on the 128-dot tape — for the
    /// typical label URL that is 29 modules × 4 dots (116) instead of
    /// 33 × 3 (99). Level L is plenty for a clean thermal print scanned
    /// up close.
    private static func qrImage(for text: String, side: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }

        let moduleCount = output.extent.width
        guard moduleCount > 0 else { return nil }
        // Reserve at least 4 dots of quiet zone on each side when picking the
        // module scale: a full-bleed QR (tried 2026-07) is not scannable.
        // The code is then centered in the full slot, so the actual margins
        // come out at 4+ dots.
        let factor = max(1, ((side - 8) / moduleCount).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
