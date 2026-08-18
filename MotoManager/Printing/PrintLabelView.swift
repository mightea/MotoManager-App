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
        NavigationStack {
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
        .navigationTitle("Etikett drucken")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schliessen") { dismiss() }
            }
        }
        .task(id: tapeRaw) {
            isRendering = true
            labelImage = await LabelRenderer.renderAsync(content: content, tape: tape)
            isRendering = false
        }
        }
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
                        .foregroundStyle(.black.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .stroke(Theme.Glass.border, lineWidth: 0.5)
            )
            Text(content.url)
                .scaledFont(10, design: .monospaced)
                .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.badge).fill(Color.primary.opacity(0.08)))
                    TextField("IP-Adresse (z. B. 192.168.1.50)", text: $printerIP)
                        .scaledFont(14, design: .monospaced)
                        .foregroundStyle(.primary)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider().padding(.leading, 56)

                Button {
                    search()
                } label: {
                    HStack(spacing: 8) {
                        if isSearching {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .scaledFont(12, weight: .bold)
                        }
                        Text(isSearching ? "Suche läuft…" : "Im Netzwerk suchen")
                            .scaledFont(13, weight: .semibold)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSearching)

                ForEach(discovered) { printer in
                Divider().padding(.leading, 56)
                    Button {
                        printerIP = printer.ipAddress
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: printerIP == printer.ipAddress
                                  ? "checkmark.circle.fill" : "circle")
                                .scaledFont(15, weight: .semibold)
                                .foregroundStyle(printerIP == printer.ipAddress
                                                 ? Theme.Colors.primary : Color.secondary.opacity(0.5))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(printer.modelName)
                                    .scaledFont(14, weight: .medium)
                                    .foregroundStyle(.primary)
                                Text(printer.ipAddress)
                                    .scaledFont(11, design: .monospaced)
                                    .foregroundStyle(.secondary)
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
                Divider().padding(.leading, 56)
                    Text("Kein Drucker gefunden. IP-Adresse manuell eingeben (auf dem Gerät: Menü → WLAN-Status).")
                        .scaledFont(11)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
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
                    ProgressView().scaleEffect(0.8)
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
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .scaledFont(10, weight: .heavy)
            .tracking(1.2)
            .foregroundStyle(.secondary)
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
