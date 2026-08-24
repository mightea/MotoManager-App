import SwiftUI

/// Searchable motorcycle picker sheet.
///
/// Native list presentation: system search field, an optional
/// "Zuletzt verwendet" horizontal chip row, then an alphabetical list of all
/// bikes with the active one pinned to the top. Each row is 52 pt thumb +
/// make/model + VETERAN badge + year/odo/plate meta. The active bike shows
/// a blue check disc on the right.
struct GarageView: View {
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @Environment(\.dismiss) var dismiss
    @State private var query: String = ""
    @State private var showingAddMotorcycle = false

    private var sortedFiltered: [Motorcycle] {
        let q = query.trim().lowercased()
        let arr: [Motorcycle] = q.isEmpty
            ? fleetVM.motorcycles
            : fleetVM.motorcycles.filter { m in
                let hay = "\(m.make) \(m.model) \(m.numberPlate ?? "") \(m.modelYear ?? "")".lowercased()
                return hay.contains(q)
            }
        return arr.sorted { a, b in
            if a.id == fleetVM.selectedMotorcycle?.id { return true }
            if b.id == fleetVM.selectedMotorcycle?.id { return false }
            return "\(a.make) \(a.model)".localizedCaseInsensitiveCompare("\(b.make) \(b.model)") == .orderedAscending
        }
    }

    private var recentBikes: [Motorcycle] {
        let activeId = fleetVM.selectedMotorcycle?.id
        return fleetVM.recentMotorcycleIds.compactMap { id in
            fleetVM.motorcycles.first(where: { $0.id == id && $0.id != activeId })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if fleetVM.motorcycles.isEmpty && !fleetVM.isLoading {
                    EmptyFleetView(onAdd: { showingAddMotorcycle = true })
                } else {
                    list
                }
            }
            .navigationTitle("Motorrad wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingAddMotorcycle) {
            AddMotorcycleView(viewModel: fleetVM) {
                showingAddMotorcycle = false
                dismiss()
            }
            .glassSheet()
        }
    }

    // MARK: - Body

    private var list: some View {
        List {
            if query.trim().isEmpty && !recentBikes.isEmpty {
                recentsSection
            }

            allSection

            Section {
                Button {
                    showingAddMotorcycle = true
                } label: {
                    Label("Motorrad hinzufügen", systemImage: "plus")
                        .scaledFont(14, weight: .semibold)
                }
                .tint(Theme.Colors.primary)
                .accessibilityLabel("Motorrad hinzufügen")
                .accessibilityIdentifier("garage.addMotorcycle")
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "Marke, Modell oder Kennzeichen …")
        // Pull to reload the fleet — the way to recover an empty picker after
        // the initial load failed offline / with the backend unreachable.
        .refreshable {
            await fleetVM.loadMotorcycles()
        }
    }

    private var recentsSection: some View {
        Section("Zuletzt verwendet") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentBikes) { motorcycle in
                        Button {
                            fleetVM.selectMotorcycle(motorcycle)
                            dismiss()
                        } label: {
                            RecentChip(motorcycle: motorcycle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var allSection: some View {
        if !query.trim().isEmpty && sortedFiltered.isEmpty {
            Section {
                ContentUnavailableView.search(text: query)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section("Alle Motorräder · \(fleetVM.motorcycles.count)") {
                ForEach(sortedFiltered) { motorcycle in
                    let isActive = fleetVM.selectedMotorcycle?.id == motorcycle.id
                    Button {
                        fleetVM.selectMotorcycle(motorcycle)
                        dismiss()
                    } label: {
                        GarageRow(motorcycle: motorcycle, isActive: isActive)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isActive ? Theme.Colors.primary.opacity(0.14) : nil)
                }
            }
        }
    }
}

// MARK: - Row

private struct GarageRow: View {
    let motorcycle: Motorcycle
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(motorcycle.make) \(motorcycle.model)")
                        .scaledFont(15, weight: .bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if motorcycle.isVeteran {
                        veteranBadge
                    }
                }
                metaLine
            }

            Spacer(minLength: 0)

            if isActive {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.primary)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .scaledFont(11, weight: .heavy)
                        .foregroundStyle(Color.white)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel("\(motorcycle.make) \(motorcycle.model)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var thumbnail: some View {
        Group {
            if let url = motorcycle.image {
                RemoteImageView(url: url, maxPixelWidth: 160)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.Colors.primary.opacity(0.2)
                    .overlay(
                        Image(systemName: "motorcycle")
                            .scaledFont(18, weight: .semibold)
                            .foregroundStyle(Theme.Colors.primary)
                    )
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }

    private var metaLine: some View {
        let plate = motorcycle.numberPlate
        let odo = motorcycle.latestOdo ?? motorcycle.initialOdo
        return HStack(spacing: 6) {
            if let year = motorcycle.modelYear.flatMap(Formatters.modelYear) {
                Text(year).monospaced()
                Text("·").opacity(0.6)
            }
            Text("\(odo) km").monospaced()
            if let plate, !plate.isEmpty {
                Text("·").opacity(0.6)
                Text(plate).monospaced()
            }
        }
        .scaledFont(11, weight: .medium)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var veteranBadge: some View {
        Text("VETERAN")
            .scaledFont(9, weight: .heavy)
            .tracking(0.4)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Theme.Colors.accent.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Recent chip

private struct RecentChip: View {
    let motorcycle: Motorcycle

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text("\(motorcycle.make) \(motorcycle.model)")
                    .scaledFont(12, weight: .bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let plate = motorcycle.numberPlate, !plate.isEmpty {
                    Text(plate)
                        .scaledFont(10, weight: .medium)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule().stroke(Theme.Glass.border, lineWidth: 0.5)
        )
        .frame(maxWidth: 200, alignment: .leading)
    }

    private var thumbnail: some View {
        Group {
            if let url = motorcycle.image {
                RemoteImageView(url: url, maxPixelWidth: 400)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.Colors.primary.opacity(0.2)
                    .overlay(
                        Image(systemName: "motorcycle")
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(Theme.Colors.primary)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

// MARK: - Helpers

private extension String {
    func trim() -> String { trimmingCharacters(in: .whitespaces) }
}

struct GarageView_Previews: PreviewProvider {
    static var previews: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                GarageView()
                    .environmentObject(MotorcycleViewModel())
                    .glassSheet()
            }
    }
}
