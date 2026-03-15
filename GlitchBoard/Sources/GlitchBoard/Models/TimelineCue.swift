import Foundation

enum CueKind: String, Codable {
    case oneShot = "one_shot"
    case range
}

enum CueInterpolation: String, Codable, CaseIterable {
    case linear
    case step
    case triangle
}

struct TimelineCue: Identifiable {
    var id: UUID
    var laneID: String
    var time: Double
    var endTime: Double?
    var label: String
    var muted: Bool
    var deviceTarget: String
    var actionID: String
    var params: [String: Double]
    var startParams: [String: Double]
    var endParams: [String: Double]
    var kind: CueKind
    var interpolation: CueInterpolation

    init(
        id: UUID = UUID(),
        laneID: String,
        time: Double,
        endTime: Double? = nil,
        label: String = "Cue",
        muted: Bool = false,
        deviceTarget: String = "",
        actionID: String = "glitchboard.cue.trigger",
        params: [String: Double] = [:],
        startParams: [String: Double] = [:],
        endParams: [String: Double] = [:],
        kind: CueKind = .oneShot,
        interpolation: CueInterpolation = .linear
    ) {
        self.id = id
        self.laneID = laneID
        self.time = time
        self.endTime = endTime
        self.label = label
        self.muted = muted
        self.deviceTarget = deviceTarget
        self.actionID = actionID
        self.params = params
        self.startParams = startParams
        self.endParams = endParams
        self.kind = kind
        self.interpolation = interpolation
    }
}
