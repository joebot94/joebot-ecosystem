import Foundation

struct TimelineCue: Identifiable, Hashable {
    let id: UUID
    let laneID: String
    var time: Double
    var label: String

    init(id: UUID = UUID(), laneID: String, time: Double, label: String = "Cue") {
        self.id = id
        self.laneID = laneID
        self.time = time
        self.label = label
    }
}
