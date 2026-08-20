import SwiftUI

/// Reusable detail-page chrome for the pushed drill-down detail views (fuel,
/// maintenance, part, storage location). Provides:
/// - A hero header (optional accent color, optional eyebrow, title, subtitle,
///   free-form children) rendered as a full-bleed row.
/// - A native insetGrouped `List` body where the caller composes
///   `DetailSection`s (plain `Section`s work too).
///
/// Designed for push presentation inside a `NavigationStack`: it shows the
/// system navigation bar (native back button + swipe-back, inline title) and
/// hides the tab bar so the detail owns the full screen. Page actions
/// (edit/delete/print) belong in the caller's `.toolbar` as standard items.
///
/// `barTitle` overrides the navigation-bar title when it should differ from
/// the hero title (e.g. fuel entries: hero shows the liters, bar the date).
/// `heroBackground` renders behind the hero (under the accent gradient) —
/// callers supply their own scrim to keep the text legible.
struct DetailPage<HeroBackground: View, HeroContent: View, BodyContent: View>: View {
    let accent: Color?
    let eyebrow: String?
    let title: String
    let barTitle: String?
    let subtitle: String?
    let photoHero: Bool?
    let heroBackground: HeroBackground
    let heroContent: HeroContent
    let bodyContent: BodyContent

    init(
        accent: Color? = nil,
        eyebrow: String? = nil,
        title: String,
        barTitle: String? = nil,
        subtitle: String? = nil,
        photoHero: Bool? = nil,
        @ViewBuilder heroBackground: () -> HeroBackground = { EmptyView() },
        @ViewBuilder heroContent: () -> HeroContent = { EmptyView() },
        @ViewBuilder body: () -> BodyContent
    ) {
        self.accent = accent
        self.eyebrow = eyebrow
        self.title = title
        self.barTitle = barTitle
        self.subtitle = subtitle
        self.photoHero = photoHero
        self.heroBackground = heroBackground()
        self.heroContent = heroContent()
        self.bodyContent = body()
    }

    /// Whether the hero sits on a photo/map and needs always-white ink.
    /// Callers whose background is *conditional* (e.g. a map only when the
    /// record has coordinates) must pass `photoHero:` explicitly — the type
    /// check alone would keep white ink even when the background is absent.
    private var hasHeroBackground: Bool { photoHero ?? (HeroBackground.self != EmptyView.self) }

    var body: some View {
        List {
            Section {
                hero
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionMargins(.all, 0)

            bodyContent
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(barTitle ?? title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            // Accent tint
            if let accent {
                LinearGradient(
                    colors: [accent.opacity(0.30), accent.opacity(0.10), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let eyebrow {
                        Text(eyebrow)
                            .scaledFont(10, weight: .heavy)
                            .tracking(1.6)
                            .foregroundStyle(hasHeroBackground ? AnyShapeStyle(Theme.Colors.onPhotoSecondary) : AnyShapeStyle(.secondary))
                    }
                    Text(title)
                        .scaledFont(26, weight: .heavy)
                        .foregroundStyle(hasHeroBackground ? AnyShapeStyle(Theme.Colors.onPhoto) : AnyShapeStyle(.primary))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .scaledFont(13, weight: .medium)
                            .foregroundStyle(hasHeroBackground ? AnyShapeStyle(Theme.Colors.onPhotoSecondary) : AnyShapeStyle(.secondary))
                    }
                    heroContent
                        .padding(.top, 6)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
            .padding(.top, 8) // nav bar provides the status-bar inset
        }
        // Sized by the hero content; sits beneath the accent gradient.
        .background { heroBackground }
        .clipped()
    }

}

// MARK: - Detail section

/// Native list section with an optional header. Kept as a named wrapper so
/// detail pages read the same as before the List migration; separators and
/// row chrome come from the system.
struct DetailSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            if let title {
                Text(title)
            }
        }
    }
}

// MARK: - Detail row

/// Single label/value row used inside `DetailSection` — a `LabeledContent`
/// with optional accent color and monospaced digits (default — toggle off
/// via `mono: false`).
struct DetailRow: View {
    let label: String
    let value: String
    var accent: Color? = nil
    var mono: Bool = true

    var body: some View {
        LabeledContent(label) {
            valueText
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var valueText: some View {
        let text = mono ? Text(value).monospacedDigit() : Text(value)
        if let accent {
            text.foregroundStyle(accent)
        } else {
            text
        }
    }
}

// MARK: - Stat tile (in-hero)

struct HeroStatTile: View {
    let eyebrow: String
    let value: String
    var unit: String? = nil
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .scaledFont(9, weight: .heavy)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .scaledFont(17, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(unit)
                    .scaledFont(10, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}
