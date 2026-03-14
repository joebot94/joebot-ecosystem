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
    let status: LaneConnectionState
    let accentHex: String
}
