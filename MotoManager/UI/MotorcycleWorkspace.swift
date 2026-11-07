import Combine
import SwiftUI

/// Shared, persistent motorcycle context above the content. On compact
/// widths a list that adopts `tracksWorkspaceHeader()` collapses the header
/// as it scrolls (see `WorkspaceHeaderState.swift`); wide layouts keep it
/// static, since two columns would fight over it. Phones present records
/// full screen: the workspace is the root of a `NavigationStack`, so a pushed
/// record covers the header as well.
struct MotorcycleWorkspace<Actions: View, Content: View>: View {
    let motorcycle: Motorcycle
    let type: HeaderType
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content
    @Environment(\.chromeActions) private var chrome
    @Environment(\.horizontalSizeClass) private var sizeClass
    // Plain `@State` holds the objects without observing them: the header
    // and the inset views subscribe, this container must not re-render on
    // every scroll tick.
    @State private var metrics = WorkspaceHeaderMetrics()
    @State private var scroll = WorkspaceScrollProgress()

    var body: some View {
        Group {
            if sizeClass == .compact {
                NavigationStack {
                    workspace
                        // The photo header replaces the bar on the root; pushed
                        // records show the system bar with the back button.
                        .toolbar(.hidden, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
            } else {
                workspace
            }
        }
        .environment(\.workspaceHeader,
                     sizeClass == .compact ? WorkspaceHeaderContext(metrics: metrics, scroll: scroll) : nil)
        .background(Theme.Colors.background)
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Short windows start with the one-row header: landscape phones,
            // and portrait phones below ~700 pt of content height (SE, large
            // Dynamic Type, Display Zoom). Height-based, not device-based.
            let condensed = (size.width > size.height && size.height < 750)
                || (sizeClass == .compact && size.height < 700)
            // Narrow or condensed headers keep two buttons (+ and the
            // switcher); settings move into the switcher's menu so the
            // name and km reading never truncate.
            let compactChrome = sizeClass == .compact && (condensed || size.width < 400)
            let body = content()
                .environment(\.workspaceIsCondensed, condensed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if sizeClass == .compact {
                // Lists scroll beneath the header and collapse it.
                body.safeAreaInset(edge: .top, spacing: 0) {
                    header(condensed: condensed, compactChrome: compactChrome)
                }
            } else {
                // Wide layouts keep the header static, so it sits above the
                // columns instead of over them; the split view's columns
                // don't reliably honour a safe-area inset (with the sidebar
                // open they started underneath the photo).
                VStack(spacing: 0) {
                    header(condensed: condensed, compactChrome: compactChrome)
                    body
                }
            }
        }
    }

    private func header(condensed: Bool, compactChrome: Bool) -> some View {
        WorkspaceHeaderSlot(metrics: metrics) {
            MotorcycleSummaryHeader(motorcycle: motorcycle, type: type, isCondensed: condensed,
                                    isNarrow: compactChrome,
                                    metrics: metrics, scroll: scroll) {
                HStack(spacing: Theme.Spacing.s) {
                    actions()
                    if !compactChrome {
                        WorkspaceAction("Einstellungen", systemImage: "gearshape", showsTitle: false) {
                            chrome.openSettings()
                        }
                    }
                }
            }
        }
    }
}

struct WorkspaceAction: View {
    let title: String
    let systemImage: String
    var showsTitle = true
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesTitle: Bool { showsTitle && sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize }

    init(_ title: String, systemImage: String, showsTitle: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.showsTitle = showsTitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: systemImage)
                if usesTitle { Text(title) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Colors.onPhoto)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, usesTitle ? Theme.Spacing.s : 0)
            .glassEffect(.regular.tint(Theme.Colors.navy950.opacity(0.5)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Native columns keep the list alive as selections and window sizes change.
/// Compact widths push the selected record onto the workspace's own
/// `NavigationStack` instead, so it takes the whole screen.
struct RecordBrowser<Selection: Hashable, Content: View, Detail: View>: View {
    @Binding var selection: Selection?
    let title: String
    let emptyTitle: String
    let systemImage: String
    var overview: AnyView? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: (Selection) -> Detail
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var columns = ColumnAlignment()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            content()
                .navigationDestination(item: $selection) { selection in
                    detail(selection)
                }
        } else {
            splitView
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            content()
                .environment(\.workspaceListTitle, title)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                // Headings and search belong to the scrolling list content.
                .toolbar(.hidden, for: .navigationBar)
                .navigationSplitViewColumnWidth(min: 330, ideal: 420, max: 560)
        } detail: {
            NavigationStack {
                if let selection {
                    detail(selection).id(selection)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            HStack {
                                Button("Zur Übersicht", systemImage: "arrow.left") {
                                    self.selection = nil
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("workspace.overview")
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.m)
                            .background(Theme.Colors.background)
                        }
                } else if let overview {
                    overview
                } else {
                    ContentUnavailableView(emptyTitle, systemImage: systemImage,
                        description: Text("Wähle links einen Eintrag, um die Details anzuzeigen."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.workspaceColumns, columns)
    }
}

// MARK: - Column alignment

/// Lines the overview's title up with the list column's title. The split
/// view insets its two columns differently, so each title reports where it
/// sits (scroll-independent) and the overview title moves down by the
/// difference.
@MainActor
final class ColumnAlignment: ObservableObject {
    @Published private(set) var listTitleY: CGFloat = 0
    @Published private(set) var overviewTitleY: CGFloat = 0
    /// Current scroll distance of each column, not published: titles only
    /// need it at measurement time to cancel out scrolling.
    fileprivate var listScroll: CGFloat = 0
    fileprivate var overviewScroll: CGFloat = 0

    var overviewOffset: CGFloat {
        guard listTitleY > 0, overviewTitleY > 0 else { return 0 }
        return max(0, (listTitleY - overviewTitleY).rounded())
    }

    func reportTitle(_ column: WorkspaceColumn, globalY: CGFloat) {
        switch column {
        case .list:
            let y = globalY + listScroll
            if abs(listTitleY - y) > 0.5 { listTitleY = y }
        case .overview:
            let y = globalY + overviewScroll
            if abs(overviewTitleY - y) > 0.5 { overviewTitleY = y }
        }
    }
}

enum WorkspaceColumn { case list, overview }

private struct WorkspaceColumnsKey: EnvironmentKey {
    static let defaultValue: ColumnAlignment? = nil
}

extension EnvironmentValues {
    var workspaceColumns: ColumnAlignment? {
        get { self[WorkspaceColumnsKey.self] }
        set { self[WorkspaceColumnsKey.self] = newValue }
    }
}

private struct ColumnScrollReader: ViewModifier {
    let column: WorkspaceColumn
    @Environment(\.workspaceColumns) private var alignment

    func body(content: Content) -> some View {
        if let alignment {
            content.onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, scrolled in
                switch column {
                case .list: alignment.listScroll = scrolled
                case .overview: alignment.overviewScroll = scrolled
                }
            }
        } else {
            content
        }
    }
}

/// Zero-height marker that reports the position of a column title's top
/// edge; `lead` is the distance from the marker down to that edge.
struct ColumnTitleMarker: View {
    let column: WorkspaceColumn
    var lead: CGFloat = 0
    @Environment(\.workspaceColumns) private var alignment

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                alignment?.reportTitle(column, globalY: y + lead)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Tracks this column's scrolling for `ColumnAlignment`. Does nothing
    /// outside a wide `RecordBrowser`.
    func alignsWorkspaceColumn(_ column: WorkspaceColumn) -> some View {
        modifier(ColumnScrollReader(column: column))
    }
}

extension View {
    func selectedRecord(_ selected: Bool) -> some View {
        listRowBackground(selected ? Theme.Colors.primary.opacity(0.12) : Theme.Colors.backgroundElevated)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WorkspaceCondensedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the workspace shows its one-row header (short windows);
    /// content uses it to pick its compact variants.
    var workspaceIsCondensed: Bool {
        get { self[WorkspaceCondensedKey.self] }
        set { self[WorkspaceCondensedKey.self] = newValue }
    }
}

private struct WorkspaceListTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var workspaceListTitle: String? {
        get { self[WorkspaceListTitleKey.self] }
        set { self[WorkspaceListTitleKey.self] = newValue }
    }
}

/// A normal list row, so titles and search scroll away with the records.
/// Compact layouts already name the section in the motorcycle header.
struct WorkspaceListHeader: View {
    var searchText: Binding<String>? = nil
    var prompt = ""
    @Environment(\.workspaceListTitle) private var title

    var body: some View {
        if title != nil || searchText != nil {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let title {
                        Text(title)
                            .background(alignment: .top) { ColumnTitleMarker(column: .list) }
                            .font(.headline)
                            // Keep the text inside the inset-grouped row's
                            // rounded clipping boundary.
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.top, Theme.Spacing.s)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("workspace.listTitle")
                    }
                    if let searchText {
                        WorkspaceSearchField(text: searchText, prompt: prompt)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionMargins(.top, Theme.Spacing.s)
            .listSectionMargins(.bottom, Theme.Spacing.s)
        }
    }
}

private struct WorkspaceSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button("Suche löschen", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: Capsule())
    }
}
