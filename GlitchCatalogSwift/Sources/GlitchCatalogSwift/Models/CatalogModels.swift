import Foundation

struct SessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var date: String
    var location: String
    var notes: String
}

struct TapeRecord: Codable, Identifiable, Hashable {
    var id: String { tapeID }
    var sessionID: UUID
    var tapeID: String
    var format: String
    var label: String
    var storageLocation: String
    var notes: String
}

struct GearRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

struct SessionGearRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var sessionID: UUID
    var gearID: UUID
    var notes: String
}

struct MediaRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var sessionID: UUID
    var filePath: String
    var kind: String
    var checksum: String
    var duration: Double
    var width: Int
    var height: Int
    var codec: String
    var createdAt: String
    var notes: String
    var thumbnailPath: String
}

struct CatalogData: Codable {
    var sessions: [SessionRecord]
    var tapes: [TapeRecord]
    var gear: [GearRecord]
    var sessionGear: [SessionGearRecord]
    var media: [MediaRecord]
}
