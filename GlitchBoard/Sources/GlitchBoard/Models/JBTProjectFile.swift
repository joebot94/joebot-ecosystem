import Foundation

struct JBTProjectFile: Codable {
    var jbtType: String
    var version: String
    var createdAt: String
    var name: String
    var payload: Payload

    enum CodingKeys: String, CodingKey {
        case jbtType = "jbt_type"
        case version
        case createdAt = "created_at"
        case name
        case payload
    }
}

extension JBTProjectFile {
    struct Payload: Codable {
        var title: String
        var audioPath: String?
        var bpm: Double
        var timeSignature: String
        var cues: [Cue]
        var deviceLanes: [DeviceLane]

        enum CodingKeys: String, CodingKey {
            case title
            case audioPath = "audio_path"
            case bpm
            case timeSignature = "time_signature"
            case cues
            case deviceLanes = "device_lanes"
        }
    }

    struct Cue: Codable {
        var id: String
        var type: String
        var bar: Int
        var beat: Int
        var timeSeconds: Double?
        var deviceID: String
        var action: String
        var params: [String: String]
        var muted: Bool
        var label: String
        var color: String?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case bar
            case beat
            case timeSeconds = "time_seconds"
            case deviceID = "device_id"
            case action
            case params
            case muted
            case label
            case color
        }
    }

    struct DeviceLane: Codable {
        var deviceID: String
        var label: String
        var color: String
        var offlineBehavior: String
        var queueTimeoutSeconds: Int

        enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case label
            case color
            case offlineBehavior = "offline_behavior"
            case queueTimeoutSeconds = "queue_timeout_seconds"
        }
    }
}
