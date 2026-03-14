import Foundation

enum LaneConnectionState: String, Hashable {
    case online
    case offline
    case connecting
}

struct CueLane: Identifiable, Hashable {
    let id: String
    let name: String
    let target: String
    var status: LaneConnectionState
    let accentHex: String
    let discoveryHints: [String]
}
