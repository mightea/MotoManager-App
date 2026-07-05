import Foundation

// DTO <-> SwiftData mapping for the parts inventory, mirroring SyncMapping.swift.
// `apply(_:)` deliberately never touches the cross-entity clientId links — those
// are local-graph knowledge the server doesn't have; only serverIds are updated.
// `toPayload(...)` takes resolved FK server ids as parameters because resolution
// (clientId -> serverId) is the SyncEngine's job at push time.

// MARK: - Part

extension SDPart {
    static func make(from dto: Part) -> SDPart {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let p = SDPart(
            clientId: cid,
            serverId: dto.id,
            partNumber: dto.partNumber,
            name: dto.name,
            syncState: .synced
        )
        p.apply(dto)
        return p
    }

    func apply(_ dto: Part) {
        serverId = dto.id
        partNumber = dto.partNumber
        name = dto.name
        manufacturer = dto.manufacturer
        partDescription = dto.description
        isPublic = dto.isPublic
        seriesIds = dto.seriesIds
        image = dto.image
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload() -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "partNumber": partNumber,
            "name": name,
            "manufacturer": manufacturer,
            "isPublic": isPublic,
            "seriesIds": seriesIds,
        ]
        if let partDescription, !partDescription.isEmpty { p["description"] = partDescription }
        return p
    }
}

// MARK: - Part stock

extension SDPartStock {
    static func make(from dto: PartStock, partClientId: UUID, storageLocationClientId: UUID?) -> SDPartStock {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let s = SDPartStock(
            clientId: cid,
            serverId: dto.id,
            partClientId: partClientId,
            partServerId: dto.partId,
            quantity: dto.quantity,
            syncState: .synced
        )
        s.storageLocationClientId = storageLocationClientId
        s.apply(dto)
        return s
    }

    func apply(_ dto: PartStock) {
        serverId = dto.id
        partServerId = dto.partId
        quantity = dto.quantity
        price = dto.price
        currency = dto.currency
        normalizedPrice = dto.normalizedPrice
        purchaseDate = dto.purchaseDate
        storageLocationServerId = dto.storageLocationId
        notes = dto.notes
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload(partServerId: Int, storageLocationServerId: Int?) -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "partId": partServerId,
            "quantity": quantity,
        ]
        if let price { p["price"] = price }
        if let currency { p["currency"] = currency }
        if let normalizedPrice { p["normalizedPrice"] = normalizedPrice }
        if let purchaseDate, !purchaseDate.isEmpty { p["purchaseDate"] = purchaseDate }
        if let storageLocationServerId { p["storageLocationId"] = storageLocationServerId }
        if let notes, !notes.isEmpty { p["notes"] = notes }
        return p
    }
}

// MARK: - Part consumption

extension SDPartConsumption {
    static func make(from dto: PartConsumption, partClientId: UUID, maintenanceClientId: UUID?) -> SDPartConsumption {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let c = SDPartConsumption(
            clientId: cid,
            serverId: dto.id,
            partClientId: partClientId,
            partServerId: dto.partId,
            maintenanceClientId: maintenanceClientId,
            maintenanceServerId: dto.maintenanceRecordId,
            quantity: dto.quantity,
            date: dto.date,
            syncState: .synced
        )
        c.apply(dto)
        return c
    }

    func apply(_ dto: PartConsumption) {
        serverId = dto.id
        partServerId = dto.partId
        maintenanceServerId = dto.maintenanceRecordId
        quantity = dto.quantity
        date = dto.date
        notes = dto.notes
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload(partServerId: Int, maintenanceRecordId: Int?) -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "partId": partServerId,
            "quantity": quantity,
            "date": date,
        ]
        if let maintenanceRecordId { p["maintenanceRecordId"] = maintenanceRecordId }
        if let notes, !notes.isEmpty { p["notes"] = notes }
        return p
    }
}

// MARK: - Storage location

extension SDStorageLocation {
    static func make(from dto: StorageLocation, parentClientId: UUID?) -> SDStorageLocation {
        let cid = dto.clientId.flatMap(UUID.init(uuidString:)) ?? UUID()
        let l = SDStorageLocation(
            clientId: cid,
            serverId: dto.id,
            name: dto.name,
            parentClientId: parentClientId,
            parentServerId: dto.parentId,
            syncState: .synced
        )
        l.apply(dto)
        return l
    }

    func apply(_ dto: StorageLocation) {
        serverId = dto.id
        name = dto.name
        parentServerId = dto.parentId
        serverUpdatedAt = dto.updatedAt
        syncState = .synced
    }

    func toPayload(parentServerId: Int?) -> [String: Any] {
        var p: [String: Any] = [
            "clientId": clientId.uuidString,
            "name": name,
        ]
        if let parentServerId { p["parentId"] = parentServerId }
        return p
    }
}
