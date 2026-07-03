import Foundation

// Mapping between API DTOs (Codable structs decoded by NetworkManager) and the
// SwiftData @Model entities, plus the create/update payloads sent to the server.
// Payload keys are camelCase to match the backend and always carry `clientId`
// so retried creates are idempotent (backend migration 011).

// MARK: - Maintenance

extension SDMaintenanceRecord {
    /// Build a fresh local model from a server DTO (used when a pull surfaces a
    /// record we don't have yet).
    static func make(from dto: MaintenanceRecord) -> SDMaintenanceRecord {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let m = SDMaintenanceRecord(
            clientId: cid,
            serverId: dto.id,
            motorcycleId: dto.motorcycleId,
            date: dto.date,
            odo: dto.odo,
            recordType: dto.recordType,
            syncState: .synced
        )
        m.apply(dto)
        return m
    }

    /// Overwrite local fields from a server DTO and mark synced.
    func apply(_ dto: MaintenanceRecord) {
        serverId = dto.id
        motorcycleId = dto.motorcycleId
        date = dto.date
        odo = dto.odo
        recordType = dto.recordType
        cost = dto.cost
        normalizedCost = dto.normalizedCost
        currency = dto.currency
        recordDescription = dto.description
        summary = dto.summary
        brand = dto.brand
        model = dto.model
        tirePosition = dto.tirePosition
        tireSize = dto.tireSize
        dotCode = dto.dotCode
        batteryType = dto.batteryType
        fluidType = dto.fluidType
        viscosity = dto.viscosity
        oilType = dto.oilType
        inspectionLocation = dto.inspectionLocation
        locationId = dto.locationId
        fuelType = dto.fuelType
        fuelAmount = dto.fuelAmount
        pricePerUnit = dto.pricePerUnit
        latitude = dto.latitude
        longitude = dto.longitude
        locationName = dto.locationName
        fuelConsumption = dto.fuelConsumption
        tripDistance = dto.tripDistance
        parentId = dto.parentId
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload() -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "date": date,
            "odo": odo,
            "type": recordType,
        ]
        if let cost { p["cost"] = cost }
        if let currency { p["currency"] = currency }
        if let pricePerUnit { p["pricePerUnit"] = pricePerUnit }
        if let fuelAmount { p["fuelAmount"] = fuelAmount }
        if let fuelType { p["fuelType"] = fuelType }
        if let recordDescription, !recordDescription.isEmpty { p["description"] = recordDescription }
        if let summary, !summary.isEmpty { p["summary"] = summary }
        if let locationName, !locationName.isEmpty { p["locationName"] = locationName }
        if let brand { p["brand"] = brand }
        if let model { p["model"] = model }
        if let tirePosition { p["tirePosition"] = tirePosition }
        if let tireSize { p["tireSize"] = tireSize }
        if let dotCode { p["dotCode"] = dotCode }
        if let batteryType { p["batteryType"] = batteryType }
        if let fluidType { p["fluidType"] = fluidType }
        if let viscosity { p["viscosity"] = viscosity }
        if let oilType { p["oilType"] = oilType }
        if let locationId { p["locationId"] = locationId }
        if let fuelConsumption { p["fuelConsumption"] = fuelConsumption }
        if let tripDistance { p["tripDistance"] = tripDistance }
        if let parentId { p["parentId"] = parentId }
        return p
    }
}

// MARK: - Torque

extension SDTorqueSpec {
    static func make(from dto: TorqueSpec) -> SDTorqueSpec {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let t = SDTorqueSpec(
            clientId: cid,
            serverId: dto.id,
            motorcycleId: dto.motorcycleId,
            category: dto.category,
            name: dto.name,
            torque: dto.torque,
            createdAt: dto.createdAt,
            syncState: .synced
        )
        t.apply(dto)
        return t
    }

    func apply(_ dto: TorqueSpec) {
        serverId = dto.id
        motorcycleId = dto.motorcycleId
        category = dto.category
        name = dto.name
        torque = dto.torque
        torqueEnd = dto.torqueEnd
        variation = dto.variation
        toolSize = dto.toolSize
        recordDescription = dto.description
        createdAt = dto.createdAt
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload() -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "category": category,
            "name": name,
            "torque": torque,
        ]
        if let torqueEnd { p["torqueEnd"] = torqueEnd }
        if let variation { p["variation"] = variation }
        if let toolSize, !toolSize.isEmpty { p["toolSize"] = toolSize }
        if let recordDescription, !recordDescription.isEmpty { p["description"] = recordDescription }
        return p
    }
}

// MARK: - Issue

extension SDIssue {
    static func make(from dto: Issue) -> SDIssue {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let i = SDIssue(
            clientId: cid,
            serverId: dto.id,
            motorcycleId: dto.motorcycleId,
            odo: dto.odo,
            title: dto.title,
            priority: dto.priority,
            status: dto.status,
            date: dto.date,
            syncState: .synced
        )
        i.apply(dto)
        return i
    }

    func apply(_ dto: Issue) {
        serverId = dto.id
        motorcycleId = dto.motorcycleId
        odo = dto.odo
        title = dto.title
        recordDescription = dto.description
        priority = dto.priority
        status = dto.status
        date = dto.date
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload() -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "odo": odo,
            "title": title,
            "priority": priority,
            "status": status,
            "date": date,
        ]
        if let recordDescription, !recordDescription.isEmpty { p["description"] = recordDescription }
        return p
    }
}
