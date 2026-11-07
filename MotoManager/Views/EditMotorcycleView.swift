import PhotosUI
import SwiftUI

/// Edit the motorcycle itself: identity, registration data, photo, and the
/// VIN (scanned off the type plate and decoded server-side into a model
/// series). Online-only, like creation — motorcycles aren't a syncable
/// SwiftData entity. Deleting the bike takes its whole history with it, so
/// that sits behind the sheet's confirmation with an explicit warning.
struct EditMotorcycleView: View {
    @ObservedObject var viewModel: MotorcycleViewModel
    let motorcycle: Motorcycle
    @EnvironmentObject private var connectivity: ConnectivityMonitor

    // Seeded from `motorcycle` in init: no declaration defaults (iOS 27 rule).
    @State private var make: String
    @State private var model: String
    @State private var fabricationDate: String
    @State private var numberPlate: String
    @State private var vin: String
    @State private var engineNumber: String
    @State private var vehicleNr: String
    @State private var fuelTankSize: String
    @State private var currency: String
    @State private var isVeteran: Bool
    @State private var hasSidecar: Bool
    @State private var seriesId: Int?
    @State private var currencies: [Currency]

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingVinScanner = false
    @State private var vinDecode: VinDecodeResult?
    @State private var vinDecodeFailed = false
    @State private var errorMessage: String?

    init(viewModel: MotorcycleViewModel, motorcycle: Motorcycle) {
        self.viewModel = viewModel
        self.motorcycle = motorcycle
        _make = State(initialValue: motorcycle.make)
        _model = State(initialValue: motorcycle.model)
        _fabricationDate = State(initialValue: motorcycle.modelYear ?? "")
        _numberPlate = State(initialValue: motorcycle.numberPlate ?? "")
        _vin = State(initialValue: motorcycle.vin ?? "")
        _engineNumber = State(initialValue: motorcycle.engineNumber ?? "")
        _vehicleNr = State(initialValue: motorcycle.vehicleNr ?? "")
        _fuelTankSize = State(initialValue: motorcycle.fuelTankSize.map { String(format: "%g", $0) } ?? "")
        _currency = State(initialValue: motorcycle.currencyCode ?? "CHF")
        _isVeteran = State(initialValue: motorcycle.isVeteran)
        _hasSidecar = State(initialValue: motorcycle.hasSidecar ?? false)
        _seriesId = State(initialValue: motorcycle.seriesId)
        _currencies = State(initialValue: CacheStore.shared.load([Currency].self, key: CacheKey.currencies) ?? [])
    }

    private var canSave: Bool {
        !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (fuelTankSize.trimmingCharacters(in: .whitespaces).isEmpty || parsedTankSize != nil)
            && connectivity.isOnline
    }

    private var parsedTankSize: Double? {
        Double(fuelTankSize.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        FormSheet(
            title: "Motorrad bearbeiten",
            canSave: canSave,
            tracked: [make, model, fabricationDate, numberPlate, vin, engineNumber, vehicleNr,
                      fuelTankSize, currency, isVeteran, hasSidecar, seriesId, pickedImage != nil],
            error: errorMessage,
            delete: FormSheetDelete(
                title: "Motorrad löschen?",
                message: "Alle Tankungen, Wartungen, Mängel, Drehmomente, Details und Dokumente von "
                    + "\(motorcycle.make) \(motorcycle.model) werden unwiderruflich gelöscht."
            ) { await viewModel.deleteMotorcycle(motorcycle) },
            onSave: save
        ) {
            photoSection
            FormField("Marke") {
                TextField("", text: $make, prompt: formPrompt("z. B. BMW"))
                    .textContentType(.organizationName)
            }
            FormField("Modell") {
                TextField("", text: $model, prompt: formPrompt("z. B. R 1250 GS"))
            }
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Baujahr") {
                    TextField("", text: $fabricationDate, prompt: formPrompt("optional"))
                        .keyboardType(.numberPad)
                }
                FormField("Kennzeichen") {
                    TextField("", text: $numberPlate, prompt: formPrompt("ZH 12345"))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            vinField
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Motornummer") {
                    TextField("", text: $engineNumber, prompt: formPrompt("optional"))
                        .autocorrectionDisabled()
                }
                FormField("Stammnummer") {
                    TextField("", text: $vehicleNr, prompt: formPrompt("optional"))
                        .autocorrectionDisabled()
                }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Tankinhalt", unit: "L",
                          hint: fuelTankSize.isEmpty || parsedTankSize != nil ? nil : "Bitte eine Zahl eingeben.") {
                    TextField("", text: $fuelTankSize, prompt: formPrompt("optional"))
                        .keyboardType(.decimalPad)
                }
                FormField("Währung") {
                    Picker("Währung", selection: $currency) {
                        ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            FormToggleRow(title: "Veteranenfahrzeug", isOn: $isVeteran)
            FormToggleRow(title: "Beiwagen", subtitle: "Schaltet die Beiwagen-Werte beim Reifendruck frei.",
                          isOn: $hasSidecar)

            if !connectivity.isOnline {
                Label("Zum Speichern ist eine Serververbindung erforderlich.", systemImage: "wifi.slash")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingVinScanner) {
            VinScanSheet { vin = $0 }
                .glassSheet()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { pickedImage = $0 }
                .ignoresSafeArea()
        }
        .task { await refreshCurrencies() }
        .task(id: vin) { await decodeVinIfPossible() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    pickedImage = image
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            FormLabel("Foto")
            Group {
                if let pickedImage {
                    Image(uiImage: pickedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let url = motorcycle.image {
                    RemoteImageView(url: url, maxPixelWidth: 1200)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.Colors.primary.opacity(0.12)
                        Image(systemName: "motorcycle")
                            .scaledFont(40)
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .stroke(Theme.Glass.border, lineWidth: 0.5)
            )
            .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.s) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Foto wählen", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .glassActionButton(.secondary, in: .roundedRectangle(radius: Theme.Radius.control))
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Label("Aufnehmen", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton(.secondary, in: .roundedRectangle(radius: Theme.Radius.control))
                }
                if pickedImage != nil {
                    Button { pickedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .glassActionButton(.secondary, in: .roundedRectangle(radius: Theme.Radius.control))
                    .accessibilityLabel("Neues Foto verwerfen")
                }
            }
        }
    }

    // MARK: - VIN

    private var vinField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormField("Fahrgestellnummer (VIN)", hint: vinHint) {
                HStack(spacing: Theme.Spacing.s) {
                    TextField("", text: $vin, prompt: formPrompt("17 Zeichen oder Rahmennummer"))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .monospaced()
                        .accessibilityLabel("Fahrgestellnummer")
                    Button {
                        showingVinScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .scaledFont(20, weight: .semibold)
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fahrgestellnummer scannen")
                }
            }
            // The decoded series links the bike to the parts catalog
            // ("Passend für …"); one tap adopts it.
            if let match = vinDecode?.match, match.id != seriesId {
                Button {
                    seriesId = match.id
                } label: {
                    Label("Baureihe «\(match.displayName)» übernehmen", systemImage: "link")
                        .scaledFont(12, weight: .semibold)
                }
                .tint(Theme.Colors.primary)
            }
        }
    }

    /// What the server made of the VIN: manufacturer, type code, model year,
    /// check digit, and the matched series — or why nothing matched.
    private var vinHint: String? {
        let trimmed = vin.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if vinDecodeFailed { return "Konnte nicht geprüft werden." }
        guard let decode = vinDecode else { return nil }
        var parts: [String] = []
        if decode.kind == "frameNumber" {
            parts.append("Rahmennummer")
        } else {
            parts.append(decode.isBmw ? "BMW" : "Kein BMW")
            if let code = decode.typeCode { parts.append("Typ \(code)") }
            if let year = decode.modelYear { parts.append("Modelljahr \(year)") }
            if decode.checkDigitValid == false { parts.append("Prüfziffer ungültig") }
        }
        if let match = decode.match {
            parts.append(match.id == seriesId ? "Baureihe \(match.displayName) verknüpft" : "erkannt: \(match.displayName)")
        } else if decode.isBmw {
            parts.append("keine Baureihe im Katalog")
        }
        return parts.joined(separator: " · ")
    }

    private func decodeVinIfPossible() async {
        vinDecode = nil
        vinDecodeFailed = false
        let trimmed = vin.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6 else { return }
        // Debounce typing; a scan result lands as one change.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            vinDecode = try await NetworkManager.shared.decodeVin(trimmed)
        } catch {
            guard !Task.isCancelled else { return }
            vinDecodeFailed = true
        }
    }

    // MARK: - Currency

    private var currencyOptions: [String] {
        var codes = currencies.map(\.code)
        if codes.isEmpty { codes = ["CHF", "EUR", "USD", "GBP"] }
        if !codes.contains(currency) { codes.insert(currency, at: 0) }
        return codes
    }

    private func refreshCurrencies() async {
        if let fresh = try? await NetworkManager.shared.fetchCurrencies() {
            currencies = fresh
        }
    }

    // MARK: - Save

    private func save() async -> Bool {
        errorMessage = nil
        guard canSave else { return false }
        // Multipart semantics: empty string clears an optional field.
        var fields: [(name: String, value: String)] = [
            ("make", make.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("model", model.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("fabricationDate", fabricationDate.trimmingCharacters(in: .whitespaces)),
            ("numberPlate", numberPlate.trimmingCharacters(in: .whitespaces)),
            ("vin", vin.trimmingCharacters(in: .whitespaces)),
            ("engineNumber", engineNumber.trimmingCharacters(in: .whitespaces)),
            ("vehicleNr", vehicleNr.trimmingCharacters(in: .whitespaces)),
            ("fuelTankSize", parsedTankSize.map { String(format: "%g", $0) } ?? ""),
            ("currencyCode", currency),
            ("isVeteran", String(isVeteran)),
            ("hasSidecar", String(hasSidecar)),
        ]
        if seriesId != motorcycle.seriesId {
            fields.append(("seriesId", seriesId.map(String.init) ?? ""))
        }
        let image = pickedImage.flatMap { Self.jpegUpload($0) }.map { (data: $0, mimeType: "image/jpeg") }
        let saved = await viewModel.updateMotorcycle(motorcycle, fields: fields, image: image)
        if !saved {
            errorMessage = viewModel.errorMessage ?? "Speichern fehlgeschlagen."
        }
        return saved
    }

    /// Downscales to a sensible upload size — phone photos are 12 MP, the
    /// header never shows more than ~1800 px.
    private static func jpegUpload(_ image: UIImage, maxPixels: CGFloat = 2000) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let scale = min(1, maxPixels / max(longest, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return scaled.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Camera

/// Minimal camera capture for the motorcycle photo. `PhotosPicker` covers
/// the library; the system camera needs UIKit.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, dismiss: dismiss) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onImage(image) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
