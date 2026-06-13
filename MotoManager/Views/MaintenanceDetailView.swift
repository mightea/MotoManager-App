import SwiftUI

/// Maintenance-record detail page matching the prototype's
/// `motomanager-app/project/assets/details/MaintenanceDetail.jsx`.
///
/// Hero uses the maintenance kind's tint as the accent and shows a small
/// pill identifying the category (Öl / Reifen / Inspektion / …). The body
/// has two stat tiles (Kosten + Bei {km}), an Übersicht section, and a
/// Notizen section. Bearbeiten + Löschen sit in the sticky action bar.
struct MaintenanceDetailView: View {
    let recordId: Int
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    init(record: MaintenanceRecord, viewModel: MotorcycleDetailViewModel) {
        self.recordId = record.id
        self.viewModel = viewModel
    }

    private var record: MaintenanceRecord? {
        viewModel.maintenanceRecords.first { $0.id == recordId }
    }

    var body: some View {
        Group {
            if let record {
                let kind = MaintenanceVisualKind.kind(for: record.recordType)
                DetailPage(
                    backLabel: "Service",
                    accent: kind.tint,
                    eyebrow: "WARTUNGSEINTRAG",
                    title: displayTitle(for: record, kind: kind),
                    subtitle: "\(formatDateFull(record.date)) · \(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
                    heroContent: { categoryPill(kind: kind) },
                    body: { sections(for: record, kind: kind) },
                    actions: { actionBar },
                    onClose: { dismiss() }
                )
            } else {
                unavailable
            }
        }
        .alert("Wartung löschen?", isPresented: $confirmingDelete) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                // Backend delete is not wired yet — keep the affordance but
                // bail out without mutating state. Replace with a real
                // viewModel.deleteMaintenance call once the API lands.
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
            Text(kind.label)
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
    private func sections(for record: MaintenanceRecord, kind: MaintenanceVisualKind) -> some View {
        HStack(spacing: 8) {
            statCard(eyebrow: "KOSTEN",
                     value: record.cost.map { formatCurrency($0, currency: currency(for: record)) } ?? "—",
                     accent: kind.tint)
            statCard(eyebrow: "BEI",
                     value: "\(record.odo) km")
        }

        DetailSection("ÜBERSICHT") {
            DetailRow(label: "Datum", value: formatDateFull(record.date), mono: false)
            divider
            DetailRow(label: "Kilometerstand", value: "\(record.odo) km")
            divider
            DetailRow(label: "Kategorie", value: kind.label, mono: false)
            divider
            DetailRow(label: "Motorrad",
                      value: "\(viewModel.motorcycle.make) \(viewModel.motorcycle.model)",
                      mono: false)
        }

        if let summary = record.summary, !summary.isEmpty {
            DetailSection("NOTIZEN") {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        } else if let desc = record.description, !desc.isEmpty {
            DetailSection("NOTIZEN") {
                Text(desc)
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.Glass.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Action bar

    private var actionBar: some View {
        Group {
            DetailActionButton("Bearbeiten", systemImage: "pencil", variant: .secondary) {
                // Edit screen for non-fuel maintenance not wired yet.
            }
            DetailActionButton("Löschen", systemImage: "trash", variant: .danger) {
                confirmingDelete = true
            }
        }
    }

    // MARK: - Unavailable

    private var unavailable: some View {
        ZStack {
            Theme.Colors.navy950.ignoresSafeArea()
            ContentUnavailableView(
                "Eintrag nicht gefunden",
                systemImage: "wrench.and.screwdriver",
                description: Text("Dieser Wartungseintrag wurde möglicherweise entfernt.")
            )
            .foregroundColor(.white)
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                            Text("Service").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .overlay(Capsule().stroke(Theme.Glass.strongBorder, lineWidth: 0.5))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Theme.Glass.hairline)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func currency(for record: MaintenanceRecord) -> String {
        record.currency ?? viewModel.motorcycle.currencyCode ?? "EUR"
    }

    private func formatCurrency(_ value: Double, currency: String) -> String {
        Formatters.currency(value, code: currency, fractionDigits: 0)
    }

    private func displayTitle(for record: MaintenanceRecord, kind: MaintenanceVisualKind) -> String {
        if let desc = record.description, !desc.isEmpty { return desc }
        if let summary = record.summary, !summary.isEmpty { return summary }
        return kind.label
    }

    private func formatDateFull(_ iso: String) -> String {
        Formatters.mediumDate(iso)
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

struct MaintenanceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MaintenanceDetailView(
                record: MotorcycleDetailViewModel.mock.maintenanceRecords[1],
                viewModel: .mock
            )
        }
    }
}
