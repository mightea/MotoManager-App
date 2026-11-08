import SwiftUI

/// Einstellungen › Offline-Dokumente: how much space the offline copies take
/// (split by motorcycle), whether opening a document keeps it, and the list
/// of kept documents to remove — one by one, several, or all.
struct OfflineDocumentsView: View {
    @ObservedObject private var store = DocumentOfflineStore.shared
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmingRemoveAll = false

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    private static func bytes(_ value: Int64) -> String { byteFormatter.string(fromByteCount: value) }

    private var items: [(entry: OfflineDocumentEntry, bytes: Int64)] {
        store.entries.values
            .map { (entry: $0, bytes: store.size(of: $0)) }
            .sorted { ($0.bytes, $0.entry.title) > ($1.bytes, $1.entry.title) }
    }

    private var total: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private var motorcycles: [Int: Motorcycle] {
        let cached: [Motorcycle] = CacheStore.shared.load([Motorcycle].self, key: CacheKey.motorcycles) ?? []
        return Dictionary(cached.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var freeSpace: Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    var body: some View {
        let items = items
        List(selection: $selection) {
            Section { usageCard(items) }
            Section {
                ForEach(OfflineSaveMode.allCases) { mode in
                    Button { store.saveMode = mode } label: {
                        HStack(spacing: Theme.Spacing.m - 4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title).font(.body.weight(.semibold))
                                Text(mode.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if store.saveMode == mode {
                                Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Theme.Colors.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.saveMode == mode ? .isSelected : [])
                    .accessibilityIdentifier("offline.mode.\(mode.rawValue)")
                }
            } header: {
                Text("Speichern")
            }
            Section {
                if items.isEmpty {
                    Text("Keine Dokumente auf diesem Gerät.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items, id: \.entry.filePath) { item in
                    row(item)
                        .tag(item.entry.filePath)
                        .swipeActions {
                            Button("Entfernen", role: .destructive) { store.remove(filePath: item.entry.filePath) }
                        }
                }
            } header: {
                HStack {
                    Text("Gespeichert")
                    Spacer()
                    if !items.isEmpty { Text("nach Grösse").textCase(nil) }
                }
            }
            if !items.isEmpty {
                Section {
                    Button("Alle Offline-Kopien entfernen", role: .destructive) { confirmingRemoveAll = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("offline.removeAll")
                } footer: {
                    Text("Entfernt nur die Kopien auf diesem Gerät. Dokumente bleiben auf dem Server, Lesezeichen bleiben erhalten.")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Offline-Dokumente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button(editMode.isEditing ? "Fertig" : "Auswählen") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            selection = []
                        }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if editMode.isEditing {
                    Button("\(selection.count) entfernen", role: .destructive) {
                        selection.forEach { store.remove(filePath: $0) }
                        selection = []
                        editMode = .inactive
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .alert("Alle Offline-Kopien entfernen?", isPresented: $confirmingRemoveAll) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) { store.removeAll() }
        } message: {
            Text("\(items.count) Dokumente, \(Self.bytes(total)). Ohne Netz sind sie danach nicht mehr lesbar; Lesezeichen bleiben erhalten.")
        }
        .accessibilityIdentifier("offline.documents")
    }

    // MARK: - Usage

    private static let palette: [Color] = [Theme.Colors.primary, Color(hex: 0x2B115A), Theme.Colors.accent, .orange, .teal]

    private func usageCard(_ items: [(entry: OfflineDocumentEntry, bytes: Int64)]) -> some View {
        let slices = OfflineStorageSummary.slices(items)
        let total = max(1, slices.reduce(0) { $0 + $1.bytes })
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.bytes(self.total)).font(.title.weight(.bold)).monospacedDigit()
                Spacer()
                Text(items.count == 1 ? "1 Dokument auf diesem \(device)" : "\(items.count) Dokumente auf diesem \(device)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                        color(slice, index)
                            .frame(width: max(4, (proxy.size.width - CGFloat(slices.count) * 2) * CGFloat(slice.bytes) / CGFloat(total)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
            .accessibilityHidden(true)
            FlowLegend(entries: slices.enumerated().map { index, slice in
                (color(slice, index), "\(name(slice)) · \(Self.bytes(slice.bytes))")
            })
            if let free = freeSpace {
                Text("\(device): \(Self.bytes(free)) frei").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func name(_ slice: OfflineStorageSummary.Slice) -> String {
        guard let id = slice.motorcycleId else { return "Mehrere Motorräder" }
        return motorcycles[id].map { $0.model } ?? "Motorrad \(id)"
    }

    private func color(_ slice: OfflineStorageSummary.Slice, _ index: Int) -> Color {
        slice.motorcycleId == nil ? .gray : Self.palette[index % Self.palette.count]
    }

    // MARK: - Rows

    private func row(_ item: (entry: OfflineDocumentEntry, bytes: Int64)) -> some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle(item.entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(Self.bytes(item.bytes)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            // Pointer-friendly remove (no hidden swipe needed on iPad).
            if UIDevice.current.userInterfaceIdiom == .pad && !editMode.isEditing {
                Button("Offline-Kopie entfernen", systemImage: "xmark") { store.remove(filePath: item.entry.filePath) }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ entry: OfflineDocumentEntry) -> String {
        var parts: [String] = []
        let names = entry.motorcycleIds.compactMap { motorcycles[$0]?.model }
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        if let opened = entry.lastOpenedAt {
            parts.append("zuletzt geöffnet " + opened.formatted(.relative(presentation: .named).locale(Formatters.displayLocale)))
        } else {
            parts.append("gespeichert " + entry.savedAt.formatted(.dateTime.day().month(.abbreviated).locale(Formatters.displayLocale)))
        }
        return parts.joined(separator: " · ")
    }
}

/// Coloured dots with labels, wrapping onto new lines.
private struct FlowLegend: View {
    let entries: [(Color, String)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m - 2) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
    }

    @ViewBuilder
    private var items: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 5) {
                Circle().fill(entry.0).frame(width: 8, height: 8)
                Text(entry.1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
