import SwiftUI

/// Searchable motorcycle picker bottom sheet.
///
/// Mirrors `motomanager-app/project/assets/sheets.jsx::MotorcyclePickerSheet`:
/// a glass bottom sheet with a sticky title + search field, an optional
/// "ZULETZT VERWENDET" horizontal chip row, then an alphabetical list of all
/// bikes with the active one pinned to the top. Each row is 52 pt thumb +
/// make/model + VETERAN badge + year/odo/plate meta. The active bike shows
/// a blue check disc on the right.
struct GarageView: View {
    @EnvironmentObject var fleetVM: MotorcycleViewModel
    @Environment(\.dismiss) var dismiss
    @State private var query: String = ""

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
        ZStack(alignment: .top) {
            sheetBackground

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 1)
                    if fleetVM.motorcycles.isEmpty && !fleetVM.isLoading {
                        EmptyFleetView()
                            .padding(.top, 40)
                    } else {
                        list
                    }
                }
                .padding(.bottom, 24)
            }
            // Pull to reload the fleet — the way to recover an empty picker after
            // the initial load failed offline / with the backend unreachable.
            .refreshable {
                await fleetVM.loadMotorcycles()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Motorrad wählen")
                        .scaledFont(17, weight: .bold)
                        .foregroundColor(.white)
                    Text(countSubtitle)
                        .scaledFont(11, weight: .medium)
                        .foregroundColor(Theme.Glass.mutedText)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(12, weight: .bold)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("Schliessen")
            }

            searchField
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(headerBlur)
    }

    private var countSubtitle: String {
        if query.trim().isEmpty {
            let count = fleetVM.motorcycles.count
            return "\(count) \(count == 1 ? "Motorrad" : "Motorräder")"
        }
        return "\(sortedFiltered.count) von \(fleetVM.motorcycles.count)"
    }

    private var headerBlur: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.Colors.navy900.opacity(0.92), location: 0.0),
                .init(color: Theme.Colors.navy900.opacity(0.92), location: 0.78),
                .init(color: Theme.Colors.navy900.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(.regularMaterial)
        .ignoresSafeArea(edges: .top)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .scaledFont(14, weight: .semibold)
                .foregroundColor(.white.opacity(0.45))

            TextField("", text: $query)
                .placeholder(when: query.isEmpty) {
                    Text("Marke, Modell oder Kennzeichen …")
                        .foregroundColor(.white.opacity(0.4))
                }
                .scaledFont(15)
                .foregroundColor(.white)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(9, weight: .heavy)
                        .foregroundColor(Theme.Colors.navy900)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                }
                .accessibilityLabel("Zurücksetzen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Glass.segmentRadius)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Glass.segmentRadius)
                .stroke(Theme.Glass.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Body

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            if query.trim().isEmpty && !recentBikes.isEmpty {
                recentsSection
            }
            allSection
            addMotorcycleRow
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ZULETZT VERWENDET")
                .scaledFont(10, weight: .heavy)
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
                .padding(.leading, 4)
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
            }
        }
    }

    @ViewBuilder
    private var allSection: some View {
        if query.trim().isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("ALLE MOTORRÄDER")
                        .scaledFont(10, weight: .heavy)
                        .tracking(1.2)
                        .foregroundColor(Theme.Glass.mutedText)
                    Text("· \(fleetVM.motorcycles.count)")
                        .scaledFont(10, weight: .heavy)
                        .tracking(1.2)
                        .foregroundColor(Theme.Glass.mutedText)
                        .monospacedDigit()
                }
                .padding(.leading, 4)
                rowsList
            }
        } else if sortedFiltered.isEmpty {
            emptyResults
        } else {
            rowsList
        }
    }

    private var rowsList: some View {
        VStack(spacing: 8) {
            ForEach(sortedFiltered) { motorcycle in
                Button {
                    fleetVM.selectMotorcycle(motorcycle)
                    dismiss()
                } label: {
                    GarageRow(
                        motorcycle: motorcycle,
                        isActive: fleetVM.selectedMotorcycle?.id == motorcycle.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyResults: some View {
        Text("Keine Motorräder gefunden für „\(query)“.")
            .scaledFont(13)
            .foregroundColor(Theme.Glass.mutedText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .stroke(Theme.Glass.border, lineWidth: 0.5)
            )
    }

    private var addMotorcycleRow: some View {
        Button {
            // Add-motorcycle picker hook — wired when garage create lands.
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.primary.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .scaledFont(16, weight: .semibold)
                        .foregroundColor(Theme.Colors.primary)
                }
                Text("Motorrad hinzufügen")
                    .scaledFont(14, weight: .semibold)
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
                    .strokeBorder(
                        Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Motorrad hinzufügen")
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: [
                Theme.Colors.navy900.opacity(0.6),
                Theme.Colors.navy950.opacity(0.8)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Row

private struct GarageRow: View {
    let motorcycle: Motorcycle
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(motorcycle.make) \(motorcycle.model)")
                        .scaledFont(15, weight: .bold)
                        .foregroundColor(.white)
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
                        .foregroundColor(.white)
                }
            }
        }
        .padding(10)
        .background(rowBackground)
        .overlay(rowBorder)
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
                        Image(systemName: "bicycle")
                            .scaledFont(18, weight: .semibold)
                            .foregroundColor(Theme.Colors.primary)
                    )
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var metaLine: some View {
        let plate = motorcycle.numberPlate
        let odo = motorcycle.latestOdo ?? motorcycle.initialOdo
        return HStack(spacing: 6) {
            if let year = motorcycle.modelYear, !year.isEmpty {
                Text(String(year.prefix(4))).monospaced()
                Text("·").opacity(0.6)
            }
            Text("\(odo) km").monospaced()
            if let plate, !plate.isEmpty {
                Text("·").opacity(0.6)
                Text(plate).monospaced()
            }
        }
        .scaledFont(11, weight: .medium)
        .foregroundColor(Theme.Glass.mutedText)
        .lineLimit(1)
    }

    private var veteranBadge: some View {
        Text("VETERAN")
            .scaledFont(9, weight: .heavy)
            .tracking(0.4)
            .foregroundColor(Theme.Colors.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Theme.Colors.accent.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 0.5)
            )
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
            .fill(
                isActive
                    ? Theme.Colors.primary.opacity(0.18)
                    : Color.white.opacity(0.06)
            )
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius)
            .stroke(
                isActive
                    ? Theme.Colors.primary.opacity(0.5)
                    : Theme.Glass.border,
                lineWidth: isActive ? 1 : 0.5
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
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let plate = motorcycle.numberPlate, !plate.isEmpty {
                    Text(plate)
                        .scaledFont(10, weight: .medium)
                        .foregroundColor(Theme.Glass.mutedText)
                        .monospaced()
                }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
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
                        Image(systemName: "bicycle")
                            .scaledFont(14, weight: .semibold)
                            .foregroundColor(Theme.Colors.primary)
                    )
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Helpers

private extension String {
    func trim() -> String { trimmingCharacters(in: .whitespaces) }
}

private extension View {
    /// Conditional placeholder for TextField (TextField's prompt does not allow color customization).
    @ViewBuilder
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
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
