import SwiftUI

/// Records, edits or deletes an odometer change (replaced instrument or
/// rolled-over counter). Online-only, like the motorcycle itself.
struct OdometerChangeSheet: View {
    @ObservedObject var viewModel: MotorcycleViewModel
    let motorcycle: Motorcycle
    let existing: OdometerChange?

    @EnvironmentObject private var connectivity: ConnectivityMonitor

    @State private var kind: String
    @State private var date: Date
    @State private var readingBefore: String
    @State private var readingAfter: String
    @State private var errorMessage: String?

    init(viewModel: MotorcycleViewModel, motorcycle: Motorcycle, existing: OdometerChange?) {
        self.viewModel = viewModel
        self.motorcycle = motorcycle
        self.existing = existing
        _kind = State(initialValue: existing?.kind ?? "replacement")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        _date = State(initialValue: existing.flatMap { formatter.date(from: $0.date) } ?? Date())
        _readingBefore = State(initialValue: existing.map { "\($0.readingBefore)" } ?? "")
        _readingAfter = State(initialValue: existing.map { "\($0.readingAfter)" } ?? "0")
        _errorMessage = State(initialValue: nil)
    }

    private var before: Int? { Self.parse(readingBefore) }
    private var after: Int? { Self.parse(readingAfter) }

    private static func parse(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        before != nil && after != nil && connectivity.isOnline
    }

    private var offsetText: String? {
        guard let before, let after else { return nil }
        let offset = before - after
        return "\(offset >= 0 ? "+" : "−") \(Formatters.kilometers(abs(offset)))"
    }

    var body: some View {
        FormSheet(
            title: existing == nil ? "Tachowechsel erfassen" : "Tachowechsel bearbeiten",
            canSave: canSave,
            tracked: [kind, readingBefore, readingAfter, Odometer.isoDay(date)],
            error: errorMessage,
            delete: existing.map { change in
                FormSheetDelete(
                    title: "Tachowechsel löschen?",
                    message: "Die Einträge seit dem Wechsel werden wieder auf den reinen Tachostand zurückgesetzt."
                ) { await viewModel.deleteOdometerChange(change, for: motorcycle) }
            },
            onSave: save
        ) {
            Text("Der Tacho wurde ersetzt oder ist übergelaufen. Du gibst weiter ein, was er zeigt; "
                + "angezeigt wird der Gesamtstand.")
                .scaledFont(13)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                FormLabel("Art")
                GlassSegmentedControl(
                    segments: [
                        .init(value: "replacement", label: "Tacho ersetzt"),
                        .init(value: "rollover", label: "Überlauf"),
                    ],
                    selection: $kind
                )
            }

            FormField("Datum des Wechsels") {
                DatePicker("Datum des Wechsels", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                FormField("Alter Tacho zeigte", unit: "km") {
                    TextField("", text: $readingBefore, prompt: formPrompt("z. B. 70000"))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("odometerChange.before")
                }
                FormField("Neuer Tacho zeigte", unit: "km") {
                    TextField("", text: $readingAfter, prompt: formPrompt("0"))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("odometerChange.after")
                }
            }

            Text("Alten Stand nicht bekannt? Schätzen, er lässt sich später korrigieren.")
                .scaledFont(12)
                .foregroundStyle(.secondary)

            if let offsetText {
                HStack {
                    Text("Versatz")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(offsetText)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .scaledFont(15)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 12)
                .background(Theme.Colors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.field))
                .accessibilityElement(children: .combine)

                if existing == nil {
                    Text("Einträge ab diesem Datum wurden mit dem neuen Tachostand erfasst und werden auf den "
                        + "Gesamtstand umgerechnet. Einträge davor bleiben unverändert.")
                        .scaledFont(12)
                        .foregroundStyle(.secondary)
                }
            }

            if !connectivity.isOnline {
                Label("Zum Speichern ist eine Serververbindung erforderlich.", systemImage: "wifi.slash")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: kind) { _, newValue in
            // A five-digit counter rolls over from 99'999 to 0.
            if newValue == "rollover", readingBefore.isEmpty {
                readingBefore = "99999"
                readingAfter = "0"
            }
        }
    }

    private func save() async -> Bool {
        errorMessage = nil
        guard let before, let after else { return false }
        let saved = await viewModel.saveOdometerChange(
            for: motorcycle, changeId: existing?.id,
            date: Odometer.isoDay(date), readingBefore: before, readingAfter: after, kind: kind)
        if !saved {
            errorMessage = viewModel.errorMessage ?? "Speichern fehlgeschlagen."
        }
        return saved
    }
}
