import Foundation

struct JBTSetlistFile: Codable {
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

extension JBTSetlistFile {
    struct Payload: Codable {
        var songs: [Song]
        var globalCueLibrary: [GlobalCue]
        var deviceLanes: [DeviceLane]
        var midiMappings: [MidiMapping]

        enum CodingKeys: String, CodingKey {
            case songs
            case globalCueLibrary = "global_cue_library"
            case deviceLanes = "device_lanes"
            case midiMappings = "midi_mappings"
        }
    }

    struct Song: Codable {
        var id: String
        var title: String
        var audioPath: String?
        var bpm: Double
        var timeSignature: String
        var cues: [Cue]
        var transition: Transition

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case audioPath = "audio_path"
            case bpm
            case timeSignature = "time_signature"
            case cues
            case transition
        }
    }

    struct Transition: Codable {
        var type: String
        var transitionCues: [Cue]

        enum CodingKeys: String, CodingKey {
            case type
            case transitionCues = "transition_cues"
        }
    }

    struct Cue: Codable {
        var id: String
        var type: String
        var bar: Int
        var beat: Int
        var endBar: Int?
        var endBeat: Int?
        var timeSeconds: Double?
        var endTimeSeconds: Double?
        var deviceID: String
        var action: String
        var params: [String: Double]
        var startParams: [String: Double]
        var endParams: [String: Double]
        var muted: Bool
        var label: String
        var color: String?
        var interpolation: String?

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case bar
            case beat
            case endBar = "end_bar"
            case endBeat = "end_beat"
            case timeSeconds = "time_seconds"
            case endTimeSeconds = "end_time_seconds"
            case deviceID = "device_id"
            case action
            case params
            case startParams = "start_params"
            case endParams = "end_params"
            case muted
            case label
            case color
            case interpolation
        }
    }

    struct GlobalCue: Codable {
        var id: String
        var name: String
        var icon: String
        var action: String
        var deviceType: String
        var params: [String: Double]
        var tags: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case icon
            case action
            case deviceType = "device_type"
            case params
            case tags
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

    struct MidiMapping: Codable {
        var midiDevice: String
        var button: [String: Int]
        var action: String
        var params: [String: Double]

        enum CodingKeys: String, CodingKey {
            case midiDevice = "midi_device"
            case button
            case action
            case params
        }
    }
}
