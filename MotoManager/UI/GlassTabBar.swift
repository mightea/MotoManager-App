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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fuel: return "Tanken"
        case .workshop: return "Werkstatt"
        case .service: return "Service"
        case .parts: return "Teile"
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .workshop: return "wrench.adjustable.fill"
        case .service: return "exclamationmark.triangle.fill"
        case .parts: return "shippingbox.fill"
        }
    }
}
