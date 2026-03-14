import Foundation

enum LaneConnectionState: String, Hashable {
    case online
    case offline
    case connecting
}

struct CueLane: Identifiable, Hashable {
    let id: String
    var name: String
    var target: String
    var status: LaneConnectionState
    let accentHex: String
    let discoveryHints: [String]
}
