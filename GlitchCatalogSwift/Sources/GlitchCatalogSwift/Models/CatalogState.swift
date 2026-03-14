import Foundation
import JoebotSDK

@MainActor
final class CatalogState: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var tapes: [TapeRecord] = []
    @Published var gear: [GearRecord] = []
    @Published var sessionGear: [SessionGearRecord] = []
    @Published var media: [MediaRecord] = []
    @Published var selectedSessionID: UUID?

    let nexusClient = NexusClient(clientId: "glitch_catalog", clientType: "catalog")

    private let store = JBTStore()

    init() {
        let data = store.load()
        sessions = data.sessions
        tapes = data.tapes
        gear = data.gear
        sessionGear = data.sessionGear
        media = data.media
        selectedSessionID = sessions.first?.id

        nexusClient.capabilitiesProvider = {
            [
                "scene_save": true,
                "jbt_storage": true,
                "snapshot": true
            ]
        }

        nexusClient.currentStateProvider = { [weak self] in
            self?.statePayload() ?? [:]
        }

        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == selectedSessionID })
    }

    var tapesForSelectedSession: [TapeRecord] {
        guard let selectedSessionID else { return [] }
        return tapes.filter { $0.sessionID == selectedSessionID }
    }

    var mediaForSelectedSession: [MediaRecord] {
        guard let selectedSessionID else { return [] }
        return media.filter { $0.sessionID == selectedSessionID }
    }

    var gearChainForSelectedSession: [String] {
        guard let selectedSessionID else { return [] }

        let links = sessionGear.filter { $0.sessionID == selectedSessionID }
        return links.compactMap { link in
            gear.first(where: { $0.id == link.gearID })?.name
        }
    }

    func sendSnapshot() {
        nexusClient.sendMessage(type: "scene_save", payload: [
            "requested_by": "glitch_catalog",
            "selected_session": selectedSession?.title ?? "none"
        ])
    }

    private func statePayload() -> [String: Any] {
        [
            "selected_session": selectedSession?.title ?? "none",
            "session_count": sessions.count,
            "tape_count": tapes.count,
            "media_count": media.count,
            "gear_chain": gearChainForSelectedSession
        ]
    }
}
