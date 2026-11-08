import Foundation

/// How one fill-up compares with the rest: consumption and price against the
/// recent average, distance and cost per km, its neighbours and the station's
/// history. Pure, so it can be tested.
struct FuelFillComparison {
    struct Fill: Equatable {
        let id: UUID
        let date: String
        let odo: Int
        let liters: Double?
        let cost: Double?
        let price: Double?
        let consumption: Double?
        let station: String?
    }

    /// Date-descending, like the fuel list.
    let fills: [Fill]
    let index: Int

    init?(fills: [Fill], id: UUID) {
        guard let index = fills.firstIndex(where: { $0.id == id }) else { return nil }
        self.fills = fills
        self.index = index
    }

    var fill: Fill { fills[index] }
    /// The older neighbour (‹).
    var previous: Fill? { fills.indices.contains(index + 1) ? fills[index + 1] : nil }
    /// The newer neighbour (›).
    var next: Fill? { index > 0 ? fills[index - 1] : nil }
    /// "1 von 7" with the newest first.
    var position: (index: Int, count: Int) { (index + 1, fills.count) }
    var isOldest: Bool { previous == nil }

    /// km since the previous fill-up; nil for the oldest or odometer glitches.
    var distance: Int? {
        guard let previous, fill.odo > previous.odo else { return nil }
        return fill.odo - previous.odo
    }

    /// Mean of the ten most recent consumptions, not counting this one.
    var averageConsumption: Double? {
        mean(fills.enumerated().filter { $0.offset != index }.compactMap { $0.element.consumption }.prefix(10))
    }

    /// This fill's consumption minus the average (L/100 km).
    var consumptionDelta: Double? {
        guard let c = fill.consumption, let avg = averageConsumption else { return nil }
        return c - avg
    }

    var averagePrice: Double? {
        mean(fills.enumerated().filter { $0.offset != index }.compactMap { $0.element.price }.filter { $0 > 0 }.prefix(10))
    }

    /// Relative price difference, e.g. 0.11 for 11 % dearer.
    var priceDelta: Double? {
        guard let p = fill.price, p > 0, let avg = averagePrice, avg > 0 else { return nil }
        return p / avg - 1
    }

    var costPerKilometer: Double? {
        guard let cost = fill.cost, cost > 0, let km = distance, km > 0 else { return nil }
        return cost / Double(km)
    }

    /// Average fuel cost per km over the other fill-ups with a distance.
    var averageCostPerKilometer: Double? {
        var values: [Double] = []
        for i in fills.indices where i != index && fills.indices.contains(i + 1) {
            let km = fills[i].odo - fills[i + 1].odo
            if km > 0, let cost = fills[i].cost, cost > 0 { values.append(cost / Double(km)) }
        }
        return mean(values.prefix(10))
    }

    /// Visits to this station so far (counting this one, up to its date) and
    /// their average price.
    var stationHistory: (visits: Int, averagePrice: Double?, lastBefore: String?)? {
        guard let name = fill.station?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let same = fills.filter { $0.station?.trimmingCharacters(in: .whitespaces) == name && $0.date <= fill.date }
        let earlier = same.filter { $0.id != fill.id }.map(\.date).max()
        return (same.count, mean(same.compactMap(\.price).filter { $0 > 0 }), earlier)
    }

    /// Consumptions oldest → newest around this fill (up to 10), with this
    /// fill's position in that window, for the trend curve.
    var trendWindow: (values: [(date: String, value: Double)], highlight: Int?) {
        let withValue = fills.enumerated().compactMap { offset, f in f.consumption.map { (offset, f.date, $0) } }
        guard !withValue.isEmpty else { return ([], nil) }
        let center = withValue.firstIndex { $0.0 >= index } ?? (withValue.count - 1)
        let lo = max(0, min(center - 4, withValue.count - 10))
        let slice = Array(withValue[lo..<min(withValue.count, lo + 10)])
        let ordered = slice.reversed().map { (date: $0.1, value: $0.2) }
        let highlight = fill.consumption == nil ? nil : ordered.firstIndex { $0.date == fill.date }
        return (Array(ordered), highlight)
    }

    private func mean<S: Sequence>(_ values: S) -> Double? where S.Element == Double {
        let array = Array(values)
        return array.isEmpty ? nil : array.reduce(0, +) / Double(array.count)
    }
}
