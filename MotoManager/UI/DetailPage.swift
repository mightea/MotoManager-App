import SwiftUI

/// Reusable detail-page chrome matching the prototype's
/// `motomanager-app/project/assets/details/DetailPage.jsx`.
///
/// Used by `FuelDetailView` and `MaintenanceDetailView`. Provides:
/// - A hero header (optional accent color, optional eyebrow, title, subtitle, free-form children).
/// - A custom **back pill** in the top-left.
/// - A scrollable body where the caller composes `DetailSection`s.
/// - An optional sticky bottom action bar with primary / secondary / danger / success buttons.
///
/// The system nav bar should be hidden where this is used so the back pill and hero own the chrome.
struct DetailPage<HeroContent: View, BodyContent: View, Actions: View>: View {
    let backLabel: String
    let accent: Color?
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let heroContent: HeroContent
    let bodyContent: BodyContent
    let actions: Actions
    let hasActions: Bool
    let onClose: () -> Void

    init(
        backLabel: String,
        accent: Color? = nil,
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder heroContent: () -> HeroContent = { EmptyView() },
        @ViewBuilder body: () -> BodyContent,
        @ViewBuilder actions: () -> Actions = { EmptyView() },
        onClose: @escaping () -> Void
    ) {
        self.backLabel = backLabel
        self.accent = accent
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.heroContent = heroContent()
        self.bodyContent = body()
        self.actions = actions()
        self.hasActions = !(Actions.self == EmptyView.self)
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(spacing: 14) {
                        bodyContent
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .background(Theme.Colors.navy950.ignoresSafeArea())

            if hasActions {
                actionBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
                backButton
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.6)
                            .foregroundColor(Theme.Glass.mutedText)
                    }
                    Text(title)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.Glass.mutedText)
                    }
                    heroContent
                        .padding(.top, 6)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
            .padding(.top, 54) // status-bar inset
        }
    }

    private var backButton: some View {
        Button(action: onClose) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .heavy))
                Text(backLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(backLabel)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            actions
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.Colors.navy950.opacity(0.0), location: 0.0),
                    .init(color: Theme.Colors.navy950.opacity(0.92), location: 0.4),
                    .init(color: Theme.Colors.navy950, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Detail row

/// Single label/value row used inside `DetailSection`. The label sits on the
/// left, the value on the right with optional accent color and monospaced
/// formatting (default — toggle off via `mono: false`).
struct DetailRow: View {
    let label: String
    let value: String
    var accent: Color? = nil
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Glass.mutedText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(accent ?? .white)
                .multilineTextAlignment(.trailing)
                .if(!mono) { $0.environment(\.font, .system(size: 14, weight: .bold)) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(Theme.Glass.mutedText)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Glass.fieldRadius))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Action button

struct DetailActionButton: View {
    let label: String
    let systemImage: String?
    let variant: Variant
    let action: () -> Void

    enum Variant { case primary, secondary, danger, success }

    init(_ label: String, systemImage: String? = nil, variant: Variant = .primary, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .glassActionButton(glassVariant, in: .roundedRectangle(radius: 14))
    }

    private var glassVariant: GlassButtonVariant {
        switch variant {
        case .primary:   .primary
        case .secondary: .secondary
        case .danger:    .danger
        case .success:   .success
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
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(Theme.Glass.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundColor(accent ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let unit {
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.Glass.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Helpers

private extension View {
    /// Apply a transform conditionally.
    @ViewBuilder
    func `if`<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition { transform(self) } else { self }
    }
}
