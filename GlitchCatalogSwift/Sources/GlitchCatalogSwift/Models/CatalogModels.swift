import Foundation
import JoebotSDK

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
    var type: String
    var source: String
    var summary: String
    var payload: [String: AnyCodable]

    var id: String {
        "\(timestamp)|\(type)|\(source)|\(summary)"
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
