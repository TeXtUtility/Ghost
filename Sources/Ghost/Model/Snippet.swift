import Foundation

struct Snippet: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var body: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, body: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.body = body
        self.createdAt = createdAt
    }
}
