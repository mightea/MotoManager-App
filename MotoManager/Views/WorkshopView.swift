import SwiftUI

struct WorkshopView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel

    private var groupedTorqueSpecs: [(category: String, specs: [TorqueSpec])] {
        Dictionary(grouping: viewModel.torqueSpecs) { $0.category }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (category: $0.key, specs: $0.value) }
    }

    private var bothEmpty: Bool {
        viewModel.torqueSpecs.isEmpty && viewModel.documents.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .workshop, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)

                if viewModel.isLoading && bothEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        GlassShimmerRow()
                            .padding(.horizontal, Theme.Spacing.s)
                    }
                } else if bothEmpty {
                    EmptyStateView(
                        title: "Workshop Empty",
                        message: "Torque specs and documents for this bike will appear here.",
                        icon: "wrench.adjustable.fill"
                    )
                    .padding(.top, 100)
                } else {
                    if !viewModel.documents.isEmpty {
                        documentsSection
                    }

                    if !viewModel.torqueSpecs.isEmpty {
                        torqueSection
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .refreshable {
            await viewModel.loadAllData()
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionHeader(label: "Manuals & Documents", count: viewModel.documents.count)
                .padding(.horizontal, Theme.Spacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(viewModel.documents) { doc in
                        DocumentCard(document: doc)
                    }
                }
                .padding(.horizontal, Theme.Spacing.s)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    // MARK: - Torque

    private var torqueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            sectionHeader(label: "Torque Specifications", count: viewModel.torqueSpecs.count)
                .padding(.horizontal, Theme.Spacing.l)

            ForEach(groupedTorqueSpecs, id: \.category) { group in
                Text(group.category.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(Theme.Colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)

                ForEach(group.specs) { spec in
                    TorqueRow(spec: spec)
                        .padding(.horizontal, Theme.Spacing.s)
                }
            }
        }
        .padding(.top, Theme.Spacing.m)
    }

    // MARK: - Helpers

    private func sectionHeader(label: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - Torque row

private struct TorqueRow: View {
    let spec: TorqueSpec

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.name)
                    .font(.headline)
                if let description = spec.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(torqueDisplay)
                    .font(.title3)
                    .bold()
                    .foregroundColor(Theme.Colors.primary)
                if let tool = spec.toolSize {
                    Text(tool)
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Radius.m)
    }

    private var torqueDisplay: String {
        if let end = spec.torqueEnd, end != spec.torque {
            return "\(Int(spec.torque))–\(Int(end)) Nm"
        }
        return "\(Int(spec.torque)) Nm"
    }
}

// MARK: - Document card

private struct DocumentCard: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Colors.primary.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(Theme.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(document.createdAt.prefix(10))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Radius.m)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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
