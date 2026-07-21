import SwiftUI

/// Sheet for printing a label on the Brother PT-E550W: live preview of the
/// rendered label, tape-width picker, printer discovery/IP and the print
/// action. Printer IP and tape width persist across sessions.
struct PrintLabelView: View {
    let content: LabelContent
    @Environment(\.dismiss) private var dismiss

    @AppStorage(LabelPrinterService.printerIPKey) private var printerIP = ""
    @AppStorage(LabelPrinterService.tapeKey) private var tapeRaw = LabelTape.mm24.rawValue

    @State private var isSearching = false
    @State private var discovered: [DiscoveredPrinter] = []
    @State private var searchedOnce = false
    @State private var isPrinting = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    // Rendered off-main after presentation so the sheet opens instantly; the
    // preview card shows a loader until the bitmap lands.
    @State private var labelImage: UIImage?
    @State private var isRendering = true

    private var tape: LabelTape { LabelTape(rawValue: tapeRaw) ?? .mm24 }
    private var canPrint: Bool {
        !isPrinting && labelImage != nil
            && !printerIP.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                previewCard
                tapePicker
                printerCard
                printButton
                statusText
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, 40)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(Color.clear)
        .task(id: tapeRaw) {
            isRendering = true
            labelImage = await LabelRenderer.renderAsync(content: content, tape: tape)
            isRendering = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Etikett drucken")
                .scaledFont(17, weight: .bold)
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .scaledFont(12, weight: .bold)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Schliessen")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .glassEffect(.regular, in: Rectangle())
    }

    // MARK: - Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("VORSCHAU")
            Group {
                if let image = labelImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 90)
                } else if isRendering {
                    ProgressView()
                        .tint(.black.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    Text("Vorschau nicht verfügbar")
                        .scaledFont(13)
                        .foregroundColor(.black.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(Theme.Glass.border, lineWidth: 0.5)
            )
            Text(content.url)
                .scaledFont(10, design: .monospaced)
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var tapePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("BANDBREITE (TZe)")
            GlassSegmentedControl(
                segments: LabelTape.allCases.map {
                    .init(value: $0.rawValue, label: $0.displayName)
                },
                selection: $tapeRaw
            )
        }
    }

    // MARK: - Printer

    private var printerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("DRUCKER")
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "printer.fill")
                        .scaledFont(13, weight: .semibold)
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10)))
                    TextField("IP-Adresse (z. B. 192.168.1.50)", text: $printerIP)
                        .scaledFont(14, design: .monospaced)
                        .foregroundColor(.white)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 56)

                Button {
                    search()
                } label: {
                    HStack(spacing: 8) {
                        if isSearching {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .scaledFont(12, weight: .bold)
                        }
                        Text(isSearching ? "Suche läuft…" : "Im Netzwerk suchen")
                            .scaledFont(13, weight: .semibold)
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSearching)

                ForEach(discovered) { printer in
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 56)
                    Button {
                        printerIP = printer.ipAddress
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: printerIP == printer.ipAddress
                                  ? "checkmark.circle.fill" : "circle")
                                .scaledFont(15, weight: .semibold)
                                .foregroundColor(printerIP == printer.ipAddress
                                                 ? Theme.Colors.primary : .white.opacity(0.35))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(printer.modelName)
                                    .scaledFont(14, weight: .medium)
                                    .foregroundColor(.white)
                                Text(printer.ipAddress)
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundColor(Theme.Glass.mutedText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if searchedOnce && !isSearching && discovered.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 56)
                    Text("Kein Drucker gefunden. IP-Adresse manuell eingeben (auf dem Gerät: Menü → WLAN-Status).")
                        .scaledFont(11)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(Theme.Glass.hairline, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Print action

    private var printButton: some View {
        Button {
            printLabel()
        } label: {
            HStack(spacing: 8) {
                if isPrinting {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "printer.fill")
                        .scaledFont(14, weight: .semibold)
                }
                Text(isPrinting ? "Wird gedruckt…" : "Drucken")
                    .scaledFont(14, weight: .semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .glassActionButton(.primary, in: .roundedRectangle(radius: 14))
        .disabled(!canPrint)
    }

    @ViewBuilder
    private var statusText: some View {
        if let successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .scaledFont(13, weight: .semibold)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .scaledFont(13, weight: .semibold)
                .foregroundColor(Theme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .scaledFont(10, weight: .heavy)
            .tracking(1.2)
            .foregroundColor(Theme.Glass.mutedText)
    }

    private func search() {
        isSearching = true
        errorMessage = nil
        Task {
            let found = await LabelPrinterService.searchPrinters()
            discovered = found
            searchedOnce = true
            isSearching = false
            if printerIP.isEmpty, let first = found.first {
                printerIP = first.ipAddress
            }
        }
    }

    private func printLabel() {
        let ip = printerIP.trimmingCharacters(in: .whitespaces)
        isPrinting = true
        successMessage = nil
        errorMessage = nil
        Task {
            // The print bitmap is the preview rotated for the tape feed —
            // rendered fresh off-main so the printer always gets 1:1 dots.
            guard let png = await LabelRenderer.renderPrintAsync(content: content, tape: tape)?.pngData() else {
                errorMessage = LabelPrintError.renderFailed.errorDescription
                isPrinting = false
                return
            }
            do {
                try await LabelPrinterService.printLabel(pngData: png, printerIP: ip, tape: tape)
                successMessage = "Etikett gedruckt."
            } catch {
                errorMessage = (error as? LabelPrintError)?.errorDescription
                    ?? error.localizedDescription
            }
            isPrinting = false
        }
    }
}
