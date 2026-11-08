import SwiftUI

/// The app's post-auth tabs. The tab bar itself is now the native iOS 26
/// Liquid Glass `TabView` (see `MainTabView`); this enum drives its `Tab`
/// items and the screen switch. (Previously this file also held a hand-rolled
/// floating glass pill, replaced by the native tab bar.)
enum AppTab: String, CaseIterable, Identifiable {
    case fuel
    case workshop
    case service
    case parts
    /// Only where the tab bar has room (`StatisticsPlacement.usesTab`).
    case statistics

    var id: String { rawValue }

    /// The tabs this device shows.
    @MainActor static var visible: [AppTab] {
        StatisticsPlacement.usesTab ? allCases : allCases.filter { $0 != .statistics }
    }

    var label: String {
        switch self {
        case .fuel: return "Tanken"
        case .workshop: return "Technik"
        case .service: return "Wartung"
        case .parts: return "Teile"
        case .statistics: return "Statistik"
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .workshop: return "wrench.adjustable.fill"
        // A checklist, not a warning triangle — the tab is routine upkeep,
        // and a permanent alert icon cries wolf.
        case .service: return "checklist"
        case .parts: return "shippingbox.fill"
        case .statistics: return "chart.bar.xaxis"
        }
    }
}
