import Foundation

/// API DTO for a motorcycle issue ("Mangel"). Decoded from `/api/motorcycles/{id}/issues`.
struct Issue: Codable, Identifiable {
    let id: Int
    let motorcycleId: Int
    let odo: Int
    let title: String
    let description: String?
    let priority: String   // "low" | "medium" | "high"
    let status: String     // "new" | "in_progress" | "done" | ...
    let date: String
    // Sync metadata (server-provided; see backend migration 011).
    let clientId: String?
    let updatedAt: String?
    let deletedAt: String?
}
