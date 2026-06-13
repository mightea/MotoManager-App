import SwiftUI

struct WorkshopView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @State private var presentedDocument: Document?
    @State private var selectedTorqueGroup: String = "Alle"

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

    private var groupedTorqueSpecs: [(category: String, specs: [TorqueSpec])] {
        Dictionary(grouping: viewModel.torqueSpecs) { $0.category }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (category: $0.key, specs: $0.value) }
    }

    private var torqueGroups: [String] {
        ["Alle"] + groupedTorqueSpecs.map { $0.category }
    }

    private var filteredTorque: [TorqueSpec] {
        if selectedTorqueGroup == "Alle" { return viewModel.torqueSpecs }
        return viewModel.torqueSpecs.filter { $0.category == selectedTorqueGroup }
    }

    private var bothEmpty: Bool {
        viewModel.torqueSpecs.isEmpty
            && viewModel.documents.isEmpty
            && viewModel.commonDocuments.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .workshop, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                if viewModel.isLoading && bothEmpty {
                    VStack(spacing: 10) {
                        ForEach(0..<5, id: \.self) { _ in
                            GlassShimmerRow().padding(.horizontal, Theme.Spacing.m)
                        }
                    }
                } else if bothEmpty {
                    EmptyStateView(
                        title: "Werkstatt leer",
                        message: "Drehmomente und Dokumente erscheinen hier.",
                        icon: "wrench.adjustable.fill"
                    )
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, 40)
                } else {
                    documentsSection
                        .padding(.horizontal, Theme.Spacing.m)
                    torqueSection
                        .padding(.horizontal, Theme.Spacing.m)
                }
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .refreshable {
            await viewModel.loadAllData()
        }
        .sheet(item: $presentedDocument) { doc in
            DocumentViewerView(document: doc)
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
                Text("\(viewModel.torqueSpecs.count) \(viewModel.torqueSpecs.count == 1 ? "Spez." : "Spez.")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 6)

            if viewModel.torqueSpecs.isEmpty {
                Text("Keine Werte erfasst.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
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
                .background(
                    Capsule()
                        .fill(active ? Theme.Colors.primary : Color.white.opacity(0.10))
                )
                .shadow(
                    color: active ? Theme.Colors.primary.opacity(0.35) : .clear,
                    radius: 8, x: 0, y: 3
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

            ForEach(Array(filteredTorque.enumerated()), id: \.element.id) { index, spec in
                TorqueRow(spec: spec, showGroup: selectedTorqueGroup == "Alle")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                if index < filteredTorque.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Torque row

private struct TorqueRow: View {
    let spec: TorqueSpec
    let showGroup: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)

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
                    if let description = spec.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(torqueDisplay)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Theme.Colors.primary)
        }
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.Colors.accent.opacity(0.16))
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 0.5)
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
        .background(
            RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                .stroke(Theme.Glass.border, lineWidth: 0.5)
        )
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
            .background(
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
