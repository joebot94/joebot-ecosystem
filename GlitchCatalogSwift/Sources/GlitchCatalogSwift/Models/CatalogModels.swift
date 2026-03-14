import Foundation
import JoebotSDK

struct SessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var date: String
    var location: String
    var notes: String
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case location
        case notes
        case tags
    }

    init(id: UUID, title: String, date: String, location: String, notes: String, tags: [String] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.location = location
        self.notes = notes
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(String.self, forKey: .date)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encode(location, forKey: .location)
        try container.encode(notes, forKey: .notes)
        try container.encode(tags, forKey: .tags)
    }
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
    var photos: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionID"
        case gearID = "gearID"
        case notes
        case photos
    }

    init(id: UUID, sessionID: UUID, gearID: UUID, notes: String, photos: [String] = []) {
        self.id = id
        self.sessionID = sessionID
        self.gearID = gearID
        self.notes = notes
        self.photos = photos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        gearID = try container.decode(UUID.self, forKey: .gearID)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try container.decodeIfPresent([String].self, forKey: .photos) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(gearID, forKey: .gearID)
        try container.encode(notes, forKey: .notes)
        try container.encode(photos, forKey: .photos)
    }
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
    var toolPath: String
    var settingsNotes: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionID"
        case filePath = "filePath"
        case kind
        case checksum
        case duration
        case width
        case height
        case codec
        case createdAt = "createdAt"
        case notes
        case thumbnailPath = "thumbnailPath"
        case toolPath = "toolPath"
        case settingsNotes = "settingsNotes"
    }

    init(
        id: UUID,
        sessionID: UUID,
        filePath: String,
        kind: String,
        checksum: String,
        duration: Double,
        width: Int,
        height: Int,
        codec: String,
        createdAt: String,
        notes: String,
        thumbnailPath: String,
        toolPath: String = "",
        settingsNotes: String = ""
    ) {
        self.id = id
        self.sessionID = sessionID
        self.filePath = filePath
        self.kind = kind
        self.checksum = checksum
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.createdAt = createdAt
        self.notes = notes
        self.thumbnailPath = thumbnailPath
        self.toolPath = toolPath
        self.settingsNotes = settingsNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        filePath = try container.decode(String.self, forKey: .filePath)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        checksum = try container.decodeIfPresent(String.self, forKey: .checksum) ?? ""
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        codec = try container.decodeIfPresent(String.self, forKey: .codec) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? ""
        toolPath = try container.decodeIfPresent(String.self, forKey: .toolPath) ?? ""
        settingsNotes = try container.decodeIfPresent(String.self, forKey: .settingsNotes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(kind, forKey: .kind)
        try container.encode(checksum, forKey: .checksum)
        try container.encode(duration, forKey: .duration)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(codec, forKey: .codec)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(notes, forKey: .notes)
        try container.encode(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(toolPath, forKey: .toolPath)
        try container.encode(settingsNotes, forKey: .settingsNotes)
    }
}

struct PresetRecord: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: String
    var snapshot: [String: AnyCodable]

    var capturedClients: [String] {
        snapshot.keys.sorted()
    }
}

struct EventLogEntry: Codable, Hashable, Identifiable {
    var timestamp: String
    var relativeMS: Double?
    var type: String
    var source: String
    var summary: String
    var payload: [String: AnyCodable]

    var id: String {
        "\(timestamp)|\(relativeMS ?? -1)|\(type)|\(source)|\(summary)"
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case relativeMS = "relative_ms"
        case type
        case source
        case summary
        case payload
    }
}

struct EventLogRecord: Codable, Hashable {
    var sessionID: String
    var sessionName: String
    var startedAt: String
    var stoppedAt: String?
    var events: [EventLogEntry]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case sessionName = "session_name"
        case startedAt = "started_at"
        case stoppedAt = "stopped_at"
        case events
    }
}

// One .jbt file contains one session plus its attached entities.
struct SessionDocument: Codable {
    var jbtType: String
    var name: String
    var session: SessionRecord
    var tapes: [TapeRecord]
    var gear: [GearRecord]
    var sessionGear: [SessionGearRecord]
    var media: [MediaRecord]
    var presets: [PresetRecord]
    var eventLog: EventLogRecord?

    enum CodingKeys: String, CodingKey {
        case jbtType = "jbt_type"
        case name
        case session
        case tapes
        case gear
        case sessionGear
        case media
        case presets
        case eventLog = "event_log"
    }

    init(
        jbtType: String = "glitch_session",
        name: String,
        session: SessionRecord,
        tapes: [TapeRecord],
        gear: [GearRecord],
        sessionGear: [SessionGearRecord],
        media: [MediaRecord],
        presets: [PresetRecord] = [],
        eventLog: EventLogRecord? = nil
    ) {
        self.jbtType = jbtType
        self.name = name
        self.session = session
        self.tapes = tapes
        self.gear = gear
        self.sessionGear = sessionGear
        self.media = media
        self.presets = presets
        self.eventLog = eventLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(SessionRecord.self, forKey: .session)
        tapes = try container.decodeIfPresent([TapeRecord].self, forKey: .tapes) ?? []
        gear = try container.decodeIfPresent([GearRecord].self, forKey: .gear) ?? []
        sessionGear = try container.decodeIfPresent([SessionGearRecord].self, forKey: .sessionGear) ?? []
        media = try container.decodeIfPresent([MediaRecord].self, forKey: .media) ?? []
        presets = try container.decodeIfPresent([PresetRecord].self, forKey: .presets) ?? []
        eventLog = try container.decodeIfPresent(EventLogRecord.self, forKey: .eventLog)
        jbtType = try container.decodeIfPresent(String.self, forKey: .jbtType) ?? "glitch_session"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? session.title
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jbtType, forKey: .jbtType)
        try container.encode(name, forKey: .name)
        try container.encode(session, forKey: .session)
        try container.encode(tapes, forKey: .tapes)
        try container.encode(gear, forKey: .gear)
        try container.encode(sessionGear, forKey: .sessionGear)
        try container.encode(media, forKey: .media)
        try container.encode(presets, forKey: .presets)
        try container.encode(eventLog, forKey: .eventLog)
    }
}

// Legacy format kept for one-time migration support.
struct CatalogData: Codable {
    var sessions: [SessionRecord]
    var tapes: [TapeRecord]
    var gear: [GearRecord]
    var sessionGear: [SessionGearRecord]
    var media: [MediaRecord]
}
