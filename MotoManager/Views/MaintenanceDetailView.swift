import SwiftUI

/// Maintenance-record detail page, backed by a SwiftData `SDMaintenanceRecord`
/// (offline-first). Hero uses the maintenance kind's tint; the sticky action bar
/// offers Bearbeiten + Löschen, both wired through the view model.
struct MaintenanceDetailView: View {
    let record: SDMaintenanceRecord
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    var body: some View {
        let kind = MaintenanceVisualKind.kind(for: record.recordType)
        DetailPage(
            backLabel: "Service",
            accent: kind.tint,
            eyebrow: record.syncState.isPending ? "WARTUNGSEINTRAG · NICHT SYNCHRON" : "WARTUNGSEINTRAG",
            title: displayTitle(kind: kind),
            subtitle: "\(Formatters.mediumDate(record.date)) · \(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
            heroContent: { categoryPill(kind: kind) },
            body: { sections(kind: kind) },
            actions: { actionBar },
            onClose: { dismiss() }
        )
        .sheet(isPresented: $showingEdit) {
            AddMaintenanceView(viewModel: viewModel, existingRecord: record)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .alert("Wartung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                viewModel.deleteMaintenance(record)
                dismiss()
            }
        } message: {
            Text("Dieser Eintrag kann nicht wiederhergestellt werden.")
        }
    }

    // MARK: - Hero pill

    private func categoryPill(kind: MaintenanceVisualKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(record.fluidTypeLabel ?? kind.label)
                .font(.system(size: 12, weight: .heavy))
        }
        .foregroundColor(kind.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(kind.tint.opacity(0.20)))
        .overlay(Capsule().stroke(kind.tint.opacity(0.35), lineWidth: 0.5))
    }

    // MARK: - Sections

    @ViewBuilder
    private func sections(kind: MaintenanceVisualKind) -> some View {
        HStack(spacing: 8) {
            statCard(eyebrow: "KOSTEN",
                     value: record.cost.map { Formatters.currency($0, code: currency, fractionDigits: 0) } ?? "—",
                     accent: kind.tint)
            statCard(eyebrow: "BEI", value: "\(record.odo) km")
        }

        DetailSection("ÜBERSICHT") {
            DetailRow(label: "Datum", value: Formatters.mediumDate(record.date), mono: false)
            divider
            DetailRow(label: "Kilometerstand", value: "\(record.odo) km")
            divider
            DetailRow(label: "Kategorie", value: record.fluidTypeLabel ?? kind.label, mono: false)
            divider
            DetailRow(label: "Motorrad",
                      value: "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
                      mono: false)
        }

        if let notes = record.recordDescription ?? record.summary, !notes.isEmpty {
            DetailSection("NOTIZEN") {
                Text(notes)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    private func statCard(eyebrow: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(accent ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Glass.hairline, lineWidth: 0.5))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        Group {
            DetailActionButton("Bearbeiten", systemImage: "pencil", variant: .secondary) {
                showingEdit = true
            }
            DetailActionButton("Löschen", systemImage: "trash", variant: .danger) {
                confirmingDelete = true
            }
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private var currency: String {
        record.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    private func displayTitle(kind: MaintenanceVisualKind) -> String {
        if let desc = record.recordDescription, !desc.isEmpty { return desc }
        if let summary = record.summary, !summary.isEmpty { return summary }
        return record.fluidTypeLabel ?? kind.label
    }
}

/// Visual mapping for maintenance kinds — duplicates the private struct in
/// `MaintenanceLogsView.swift` so both files can render the same icon + tint.
struct MaintenanceVisualKind {
    let label: String
    let icon: String
    let tint: Color

    static func kind(for type: String) -> MaintenanceVisualKind {
        switch type.lowercased() {
        case "oil", "engineoil", "gearboxoil", "finaldriveoil", "forkoil":
            return .init(label: "Öl", icon: "drop.fill", tint: .green)
        case "tire", "tires":
            return .init(label: "Reifen", icon: "circle.dotted", tint: Color(hex: 0x0EA5E9))
        case "inspection":
            return .init(label: "Inspektion", icon: "list.clipboard.fill", tint: .orange)
        case "chain":
            return .init(label: "Antrieb", icon: "link", tint: .purple)
        case "brakes", "brakefluid":
            return .init(label: "Bremsen", icon: "hammer.fill", tint: Theme.Colors.accent)
        case "battery", "electric":
            return .init(label: "Elektrik", icon: "bolt.fill", tint: Color(hex: 0xF59E0B))
        case "coolant", "fluid":
            return .init(label: "Kühler", icon: "drop.halffull", tint: Color(hex: 0x0EA5E9))
        default:
            return .init(label: type.capitalized, icon: "wrench.and.screwdriver.fill", tint: Theme.Colors.primary)
        }
    }
}
