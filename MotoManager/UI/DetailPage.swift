import SwiftUI

/// Reusable detail-page chrome matching the prototype's
/// `motomanager-app/project/assets/details/DetailPage.jsx`.
///
/// Used by the pushed drill-down detail views (fuel, maintenance, part,
/// storage location). Provides:
/// - A hero header (optional accent color, optional eyebrow, title, subtitle, free-form children).
/// - A scrollable body where the caller composes `DetailSection`s.
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
    let heroBackground: HeroBackground
    let heroContent: HeroContent
    let bodyContent: BodyContent

    init(
        accent: Color? = nil,
        eyebrow: String? = nil,
        title: String,
        barTitle: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder heroBackground: () -> HeroBackground = { EmptyView() },
        @ViewBuilder heroContent: () -> HeroContent = { EmptyView() },
        @ViewBuilder body: () -> BodyContent
    ) {
        self.accent = accent
        self.eyebrow = eyebrow
        self.title = title
        self.barTitle = barTitle
        self.subtitle = subtitle
        self.heroBackground = heroBackground()
        self.heroContent = heroContent()
        self.bodyContent = body()
    }

    /// Whether the hero sits on a photo/scrim (caller passed a background).
    /// Photo heroes keep white ink; plain heroes use adaptive label colors.
    private var hasHeroBackground: Bool { HeroBackground.self != EmptyView.self }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(spacing: 14) {
                    bodyContent
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
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
                .ignoresSafeArea(edges: .top)
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

// MARK: - Detail row

/// Single label/value row used inside `DetailSection`. The label sits on the
/// left, the value on the right with optional accent color and monospaced
/// digits (default — toggle off via `mono: false`).
struct DetailRow: View {
    let label: String
    let value: String
    var accent: Color? = nil
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(13, weight: .medium)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            valueText
                .scaledFont(14, weight: .bold)
                .foregroundStyle(accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var valueText: some View {
        if mono {
            Text(value).monospacedDigit()
        } else {
            Text(value)
        }
    }
}

// MARK: - Detail section

/// Card-grouped section with optional eyebrow title. Children stack with
/// 0.5pt dividers between rows.
struct DetailSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .scaledFont(10, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
