import Foundation

/// On-disk Codable cache for backend responses, used to keep the app usable offline.
///
/// Files live under `Application Support/MotoCache/` so the system does not purge them
/// under disk pressure (unlike `Caches/`). Cleared on logout via ``clearAll()``.
final class CacheStore {
    static let shared = CacheStore()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = support.appendingPathComponent("MotoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func save<T: Encodable>(_ value: T, key: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            AppLog.error("CacheStore: failed to save \(key): \(error.localizedDescription)")
        }
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

enum CacheKey {
    static let motorcycles = "motorcycles"
    static let documents = "documents"
    static let currencies = "currencies"
    static let modelSeries = "modelSeries"

    static func maintenance(motorcycleId: Int) -> String { "maintenance_\(motorcycleId)" }
    static func torque(motorcycleId: Int) -> String { "torque_\(motorcycleId)" }
    static func tirePressure(motorcycleId: Int) -> String { "tirePressure_\(motorcycleId)" }
}
