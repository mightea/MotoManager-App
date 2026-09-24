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
            let condensed = geometry.size.width > geometry.size.height && geometry.size.height < 750
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    WorkspaceHeaderSlot(metrics: metrics) {
                        MotorcycleSummaryHeader(motorcycle: motorcycle, type: type, isCondensed: condensed,
                                                metrics: metrics, scroll: scroll) {
                            HStack(spacing: Theme.Spacing.s) {
                                actions()
                                WorkspaceAction("Einstellungen", systemImage: "gearshape", showsTitle: false) {
                                    chrome.openSettings()
                                }
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
    }
}

extension View {
    func selectedRecord(_ selected: Bool) -> some View {
        listRowBackground(selected ? Theme.Colors.primary.opacity(0.12) : Theme.Colors.backgroundElevated)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
