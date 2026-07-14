import SwiftUI

struct WorkshopView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var presentedDocument: Document?
    @State private var selectedTorqueGroup: String = "Alle"
    @State private var showingAddTorque = false
    @State private var editingTorque: SDTorqueSpec?
    @State private var showingTirePressure = false

    enum DocScope: Hashable { case moto, common }
    @State private var docScope: DocScope = .moto

    private var displayedDocuments: [Document] {
        switch docScope {
        case .moto: return viewModel.documents
        case .common: return viewModel.commonDocuments
        }
    }

    private var motoLabel: String {
        let make = viewModel.motorcycle.make
        let model = viewModel.motorcycle.model
        let full = "\(make) \(model)"
        return full.count > 14 ? make : full
    }

    private var groupedTorqueSpecs: [(category: String, specs: [SDTorqueSpec])] {
        Dictionary(grouping: viewModel.torque) { $0.category }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (category: $0.key, specs: $0.value) }
    }

    private var torqueGroups: [String] {
        ["Alle"] + groupedTorqueSpecs.map { $0.category }
    }

    private var filteredTorque: [SDTorqueSpec] {
        if selectedTorqueGroup == "Alle" { return viewModel.torque }
        return viewModel.torque.filter { $0.category == selectedTorqueGroup }
    }

    private var bothEmpty: Bool {
        viewModel.torque.isEmpty
            && viewModel.documents.isEmpty
            && viewModel.commonDocuments.isEmpty
            && viewModel.tirePressure == nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .workshop, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                if viewModel.isLoading && bothEmpty {
                    VStack(spacing: 10) {
                        ForEach(0..<5, id: \.self) { _ in
                            GlassShimmerRow().padding(.horizontal, Theme.Spacing.pageH)
                        }
                    }
                } else if bothEmpty {
                    EmptyStateView(
                        title: "Werkstatt leer",
                        message: "Drehmomente und Dokumente erscheinen hier.",
                        icon: "wrench.adjustable.fill"
                    )
                    .padding(.horizontal, Theme.Spacing.pageH)
                    .padding(.top, 40)
                } else {
                    tirePressureSection
                        .padding(.horizontal, Theme.Spacing.pageH)
                    documentsSection
                        .padding(.horizontal, Theme.Spacing.pageH)
                    torqueSection
                        .padding(.horizontal, Theme.Spacing.pageH)
                }
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        // Banner only — Workshop's adds are per-section, so no page-level button.
        .bottomActionBar(detailVM: viewModel)
        .refreshable {
            await viewModel.reconnect()
        }
        .sheet(item: $presentedDocument) { doc in
            DocumentViewerView(document: doc)
        }
        .sheet(isPresented: $showingAddTorque) {
            AddTorqueView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTorque) { spec in
            AddTorqueView(viewModel: viewModel, existingSpec: spec)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTirePressure) {
            AddTirePressureView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Glass.sheetRadius)
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tire pressure

    private var tirePressureSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Reifendruck".uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Button { showingTirePressure = true } label: {
                    Image(systemName: viewModel.tirePressure == nil ? "plus" : "pencil")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 26, height: 26)
                }
                .glassActionButton(.primary, in: .circle)
                .accessibilityLabel(viewModel.tirePressure == nil ? "Reifendruck erfassen" : "Reifendruck bearbeiten")
            }
            .padding(.horizontal, 6)

            if let pressure = viewModel.tirePressure {
                TirePressureTable(pressure: pressure)
            } else {
                Button { showingTirePressure = true } label: {
                    Text("Keine Werte erfasst — tippen zum Hinzufügen.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Dokumente".uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(displayedDocuments.count) \(displayedDocuments.count == 1 ? "Eintrag" : "Einträge")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 6)

            GlassSegmentedControl(
                segments: [
                    .init(value: .moto, label: motoLabel),
                    .init(value: .common, label: "Allgemein")
                ],
                selection: $docScope
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(displayedDocuments) { doc in
                    Button {
                        presentedDocument = doc
                    } label: {
                        DocumentTile(document: doc)
                    }
                    .buttonStyle(.plain)
                }
                UploadDocumentTile {
                    // Upload picker hook — wired when document upload lands.
                }
            }
        }
    }

    // MARK: - Torque

    private var torqueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("Drehmoment-Spezifikationen".uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Button { showingAddTorque = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .heavy))
                        .frame(width: 26, height: 26)
                }
                .glassActionButton(.primary, in: .circle)
                .accessibilityLabel("Drehmoment hinzufügen")
            }
            .padding(.horizontal, 6)

            if viewModel.torque.isEmpty {
                Button { showingAddTorque = true } label: {
                    Text("Keine Werte erfasst — tippen zum Hinzufügen.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(torqueGroups, id: \.self) { group in
                            chip(group)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                torqueTable
            }
        }
    }

    private func chip(_ label: String) -> some View {
        let active = label == selectedTorqueGroup
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedTorqueGroup = label
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(active ? .white : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(
                    active
                        ? .regular.tint(Theme.Colors.primary).interactive()
                        : .regular.interactive(),
                    in: Capsule()
                )
        }
    }

    private var torqueTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BAUTEIL")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("DREHMOMENT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            ForEach(Array(filteredTorque.enumerated()), id: \.element.clientId) { index, spec in
                Button { editingTorque = spec } label: {
                    TorqueRow(spec: spec, showGroup: selectedTorqueGroup == "Alle")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if index < filteredTorque.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Tire pressure table

/// Matrix of the recorded pressures: one row per tire position (Vorne /
/// Hinten / Beiwagen), one column per recorded riding configuration —
/// mirrors the webapp card. Column headers only render when they carry
/// information (several configurations, or a single non-solo one).
private struct TirePressureTable: View {
    let pressure: TirePressure

    private var configs: [PressureConfig] { pressure.recordedConfigs }

    private var showHeader: Bool {
        configs.count > 1 || configs.contains { $0 != .solo }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                HStack {
                    Color.clear.frame(width: 70, height: 1)
                    ForEach(configs) { cfg in
                        Text(cfg.label.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
            }

            row(label: "Vorne") { $0.front }
            Divider().background(Color.white.opacity(0.06))
            row(label: "Hinten") { $0.rear }
            if pressure.hasSidecarValues {
                Divider().background(Color.white.opacity(0.06))
                row(label: "Beiwagen") { $0.sidecar }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(
        label: String,
        value: @escaping ((front: Double?, rear: Double?, sidecar: Double?)) -> Double?
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            ForEach(configs) { cfg in
                cell(bar: value(pressure.values(for: cfg)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func cell(bar: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let bar {
                Text(PressureUnitFormat.display(bar: bar, unit: pressure.preferredUnit))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Colors.primary)
                Text(PressureUnitFormat.secondary(bar: bar, unit: pressure.preferredUnit))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
    }
}

// MARK: - Torque row

private struct TorqueRow: View {
    let spec: SDTorqueSpec
    let showGroup: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(spec.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if spec.syncState.isPending { PendingBadge() }
                    if spec.unverified {
                        Label("Unverifiziert", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundColor(.orange)
                    }
                }

                if showGroup || (spec.toolSize.map { !$0.isEmpty } ?? false) {
                    HStack(spacing: 6) {
                        if showGroup {
                            Text(spec.category.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.4)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Theme.Colors.primary.opacity(0.22)))
                                .foregroundColor(Theme.Colors.primary)
                        }
                        if let tool = spec.toolSize, !tool.isEmpty {
                            Text(tool)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }

                // Full description on its own line so it wraps and the row grows
                // vertically instead of truncating.
                if let description = spec.recordDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(torqueDisplay)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundColor(spec.unverified ? .orange : Theme.Colors.primary)
        }
        .contentShape(Rectangle())
    }

    private var torqueDisplay: String {
        if let end = spec.torqueEnd, end != spec.torque {
            return "\(Int(spec.torque))–\(Int(end)) Nm"
        }
        return "\(Int(spec.torque)) Nm"
    }
}

// MARK: - Document tile

private struct DocumentTile: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                DocumentThumbnailView(document: document)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                Text(fileBadge)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.4)
                    .foregroundColor(Theme.Colors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.accent.opacity(0.22))
                    )
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(document.createdAt.prefix(10))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
    }

    private var fileBadge: String {
        let ext = (document.filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "PDF"
        case "jpg", "jpeg", "png", "heic", "heif": return "IMG"
        case "": return "DOC"
        default: return ext.uppercased()
        }
    }
}

private struct UploadDocumentTile: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text("Hochladen")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 132)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .strokeBorder(
                        Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dokument hochladen")
    }
}

struct WorkshopView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            WorkshopView(viewModel: .mock)
        }
    }
}
