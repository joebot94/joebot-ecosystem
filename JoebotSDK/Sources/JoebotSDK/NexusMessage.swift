import Foundation

public struct NexusMessage: Codable {
    public let id: String
    public let type: String
    public let source: String
    public let payload: [String: AnyCodable]

    public init(id: String, type: String, source: String, payload: [String: AnyCodable] = [:]) {
        self.id = id
        self.type = type
        self.source = source
        self.payload = payload
    }
}

public struct NexusClientInfo: Identifiable, Codable, Hashable {
    public var id: String { clientId }
    public let clientId: String
    public let clientType: String
    public var online: Bool
    public var lastSeen: String?
    public var stateSummary: String

    public init(clientId: String, clientType: String, online: Bool, lastSeen: String? = nil, stateSummary: String = "No state yet") {
        self.clientId = clientId
        self.clientType = clientType
        self.online = online
        self.lastSeen = lastSeen
        self.stateSummary = stateSummary
    }
}
