import Combine
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
    private var subscriptions: Set<AnyCancellable> = []
    private var documentsBySessionID: [UUID: SessionDocument] = [:]

    init() {
        loadSessionDocuments()

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

        // Forward NexusClient updates so UI banners and controls stay current.
        nexusClient.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        nexusClient.connect(to: "127.0.0.1", port: 8675)
    }

    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return documentsBySessionID[selectedSessionID]?.session
    }

    var tapesForSelectedSession: [TapeRecord] {
        tapes
    }

    var mediaForSelectedSession: [MediaRecord] {
        media
    }

    var gearChainForSelectedSession: [String] {
        let linkedGearIDs = sessionGear.map(\.gearID)
        return linkedGearIDs.compactMap { gearID in
            gear.first(where: { $0.id == gearID })?.name
        }
    }

    func selectSession(_ sessionID: UUID?) {
        selectedSessionID = sessionID

        guard let sessionID, let document = documentsBySessionID[sessionID] else {
            tapes = []
            gear = []
            sessionGear = []
            media = []
            return
        }

        tapes = document.tapes
        gear = document.gear
        sessionGear = document.sessionGear
        media = document.media
    }

    func createSession(title: String, date: String, location: String, notes: String) {
        let session = SessionRecord(
            id: UUID(),
            title: title,
            date: date,
            location: location,
            notes: notes
        )

        let document = SessionDocument(
            session: session,
            tapes: [],
            gear: [],
            sessionGear: [],
            media: []
        )

        documentsBySessionID[session.id] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: session.id)
    }

    func updateSelectedSession(title: String, date: String, location: String, notes: String) {
        guard let selectedSessionID, var document = documentsBySessionID[selectedSessionID] else { return }

        document.session.title = title
        document.session.date = date
        document.session.location = location
        document.session.notes = notes

        documentsBySessionID[selectedSessionID] = document
        store.saveSessionDocument(document)
        refreshSessionIndex(selecting: selectedSessionID)
    }

    func deleteSelectedSession() {
        guard let selectedSessionID else { return }
        documentsBySessionID[selectedSessionID] = nil
        store.deleteSessionDocument(sessionID: selectedSessionID)

        let nextSelection = sessions
            .filter { $0.id != selectedSessionID }
            .sorted { $0.date > $1.date }
            .first?
            .id

        refreshSessionIndex(selecting: nextSelection)
    }

    func sendSnapshot() {
        nexusClient.sendMessage(type: "scene_save", payload: [
            "requested_by": "glitch_catalog",
            "selected_session": selectedSession?.title ?? "none"
        ])
    }

    static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parse(dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString) ?? Date()
    }

    private func loadSessionDocuments() {
        let docs = store.loadSessionDocuments()
        documentsBySessionID = Dictionary(uniqueKeysWithValues: docs.map { ($0.session.id, $0) })
        refreshSessionIndex(selecting: docs.first?.session.id)
    }

    private func refreshSessionIndex(selecting preferredID: UUID?) {
        sessions = documentsBySessionID.values
            .map(\.session)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.date > rhs.date
            }

        let targetID = preferredID ?? sessions.first?.id
        selectSession(targetID)
    }

    private func statePayload() -> [String: Any] {
        [
            "selected_session": selectedSession?.title ?? "none",
            "session_count": sessions.count,
            "tape_count": tapesForSelectedSession.count,
            "media_count": mediaForSelectedSession.count,
            "gear_chain": gearChainForSelectedSession
        ]
    }
}
